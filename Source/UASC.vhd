--------------------------------------------------------------------------------
--  File Name    : UART.vhd
--  Author       : Jean-Stephane Cote
--  Date         : 2025-01-05
--  Version      : 1.0
--
--  Description  : Standard full duplex UART module. No oversampling.
--
--  Dependencies : ieee.std_logic_1164.all 
--
--  Revision History:
--    Ver  Date         Author               Description
--    ---  -----------  ------------------  ------------------------------------------
--    1.0  2025-01-05   Jean-Stephane Cote   Initial Revision
--
--------------------------------------------------------------------------------
--  The MIT License (MIT)
--
--  Copyright (c) <2025> <Jean-Stphane Cote>
--
--
--  Permission is hereby granted, free of charge, to any person obtaining a copy
--  of this software and associated documentation files (the "Software"), to deal
--  in the Software without restriction, including without limitation the rights
--  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--  copies of the Software, and to permit persons to whom the Software is
--  furnished to do so, subject to the following conditions:
--
--  The above copyright notice and this permission notice shall be included in all
--  copies or substantial portions of the Software.
--
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--  SOFTWARE.

--------------------------------------------------------------------------------


--=========================================================================================
--| Start Bit | Data bits (N_data) | Parity bit (None, odd or even) | Stop bit (1 or 2) |--
--=========================================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

    entity UART is
        generic( 
            -- UART bit settings
            N_data      :    integer range 5 to 9               := 8;       -- Number of data bits
            N_parity    :    integer range 0 to 1               := 0;       -- Number of parity bits
            N_stop      :    integer range 1 to 2               := 1;       -- Number of stop bits
            Parity_type :    std_logic                          := '0';     -- Parity type. 0 = odd, 1 = even. If no parity, dont care

            -- UART baud rate settings
            CLOCKFREQ   :    natural                            := 10e6;    -- Frquency in Hz
            Baud        :    integer range 9600 to 1_500_000    := 9600    -- Baud rate in bps
        );

        port (
            -- System signals
            clk     : in std_logic;                                         -- System clock
            reset   : in std_logic;                                         -- Active high reset

            -- Parallele data interface
            data_to_send    : in std_logic_vector (N_data-1 downto 0);      -- Parallele data to send through the UART
            data_received   : out std_logic_vector (N_data-1 downto 0);     -- Parallele data received through the UART

            -- Control signals / flags
            send_data       : in std_logic;                                 -- Send data signal
            Error           : out std_logic;                                -- Error signal

            -- UART two wire standard inteface
            RX      : in std_logic;                                         -- Serial data input
            TX      : out std_logic                                         -- Serial data output
        );
    end entity UART;

    architecture rtl of UART is

        -- Baud Generators 
        signal max_counter              : integer   := 0 ;      -- Maximum counter value to generate the baud rate
        signal counter_TX               : integer   := 0 ;      -- Counter to keep track of the baud rate generation for transmission
        signal tmp_TX                   : std_logic := '0';     -- Pulsed signal at the baud rate interval for transmission
        signal counter_RX               : integer   := 0 ;      -- Counter to keep track of the baud rate generation for reception
        signal tmp_RX                   : std_logic := '0';     -- Pulsed signal at the baud rate interval for reception

        -- Transmission signals
        signal transmit_bit_position        : integer   :=  0 ;     -- Data bit position in the data_to_send vector
        signal parity_TX                : std_logic := '0';     -- Keeping track of the parity of the data bits 
        signal N_stop_bits_tx           : integer   :=  0;      -- Keeping track of the number of stop bits sent

        -- Reception signals
        signal reception_bit_position   : integer   := 0;       -- Data bit position in the data_to_send vector
        signal parity_RX                : std_logic := '0';     -- Keeping track of the parity of the data bits
        signal N_stop_bits_rx           : integer   := 0;       -- Keeping track of the number of stop bits received
        signal reception_init           : integer   := 0;       -- Reception initialization counter
        signal Error_buffer             : std_logic := '0';     -- Error buffer to keep track of the reception errors
        constant RX_Buffer_size         : integer   := 10;      -- Buffer size for the reception initialization

        -- Latch
        signal data_latch_TX             : std_logic_vector (N_data-1 downto 0) := (others => '0');     -- Data received from the UART

        
        -- UART standard state machine with framing and data 
        type uart_states is (       
            idle,
            start_bit,
            data_bits,
            parity_bits,
            stop_bits);

        signal Transmit_current_state, Transmit_next_state     : uart_states := idle;
        signal Receive_current_state, Receive_next_state       : uart_states := idle;

    begin
        
        max_counter <= integer(CLOCKFREQ / Baud);        -- Dictats the number of clock ticks till the next bit is sent or received 

        --====================================================================================
        --=================================Transmissions ======================================
        --====================================================================================

        --============================== Baud Generator ======================================

        Baud_Generator_TX : process(clk, reset)
        begin
            -- Reset the baud Generator
            if (reset = '1') then
                counter_TX <= 0;
                tmp_TX <= '0';

            -- Baud generator creates a one clock pulse at every baud rate interval
            elsif (rising_edge(clk)) then
                if (Transmit_current_state /= idle or send_data = '1') then     -- send data needs to stay high for the first baud cycle to initiate the transmission
                    if (counter_TX = max_counter-1) then
                        tmp_TX <= '1' ;
                        counter_TX <= 0;
                    else
                        counter_TX <= counter_TX + 1;
                        tmp_TX <= '0';
                    end if;
                else 
                    counter_TX <= 0;
                    tmp_TX <= '0';
                end if;
            end if;
        end process;

        --===================== Transmitter Logic =================================


        -- Transmitters next state logic. Not Clocked.
        Transmission_State_Transition : process (reset, send_data, transmit_bit_position, Transmit_current_state, N_stop_bits_tx)
        begin
            if(reset = '1') then
                Transmit_next_state <= idle;
            else
                case Transmit_current_state is

                    -- Idle state waits for the send_data signal to be high to start the transmission
                    when idle =>    
                        if(send_data = '1') then
                            Transmit_next_state <= start_bit;
                        else
                            Transmit_next_state <= idle;
                        end if;

                    -- Always goes to data bits. No conditions
                    when start_bit => 
                        Transmit_next_state <= data_bits;
                            
                    -- Cycles through the data bits until N_data is reached. Either goes to parity or stop bits depending on the parity settings 
                    when data_bits => 
                        if ((transmit_bit_position) = N_data) then
                            if (N_parity = 0) then
                                Transmit_next_state <= stop_bits;
                            else
                                Transmit_next_state <= parity_bits;
                            end if;
                        else
                            Transmit_next_state <= data_bits;
                        end if;

                    -- Always goes to stop bits. No conditions
                    when parity_bits =>
                        Transmit_next_state <= stop_bits;

                    -- Cycles through the stop bits until N_stop is reached. Either goes back to idle or stop bits depending on the number of stop bits selected
                    when stop_bits => 
                        if (N_stop_bits_tx = N_stop) then
                            Transmit_next_state <= idle;
                        else
                            Transmit_next_state <= stop_bits;
                        end if;
                        
                end case;
            end if;
        end process;

        -- Transmitters outputs logic. Also used to set the current state. Clocked.
        Transmission_output_and_transition : process(reset, clk)
            begin
            if(reset = '1') then
                TX <= '1';
                Transmit_current_state <= idle;
                parity_TX <= '0';
                transmit_bit_position <= 0;
                N_stop_bits_tx <= 0;

            elsif (rising_edge(clk)) then
                if (tmp_TX = '1') then      -- Only updates the state at the baud rate interval (pulse)

                Transmit_current_state <= Transmit_next_state;

                case Transmit_next_state is 

                        -- Idle state sets the TX line to 1 (High), resets the parity, stop bits counters and transmit bit position
                        when idle =>               
                            TX <= '1';
                            parity_TX <= '0';
                            transmit_bit_position <= 0;
                            N_stop_bits_tx <= 0;

                        -- Start bit sets the TX line to 0 indicating the start of the transmission
                        when start_bit =>         
                            TX <='0';
                            data_latch_TX <= data_to_send;

                        -- Data bits sends the data bits one by one until N_data is reached. also calculates the parity.
                        when data_bits =>
                            TX <= data_latch_TX(transmit_bit_position);
                            parity_TX <= parity_TX xor data_latch_TX(transmit_bit_position);
                            transmit_bit_position <= transmit_bit_position + 1;

                        -- Sends the parity bit depending on the parity type selected in the generic
                        when parity_bits =>
                            if (Parity_type = '1') then     -- If even parity was selected
                                TX <= not parity_TX;
                            else                            -- If odd parity was selected
                                TX <= parity_TX;
                            end if;

                        -- Sends the stop bits depending on the number of stop bits selected in the generic
                        when stop_bits =>
                            TX <= '1';
                            N_stop_bits_tx <= N_stop_bits_tx + 1;

                    end case;
                end if;
            end if;
        end process;
                
        --====================================================================================
        --================================ Reception ---======================================
        --====================================================================================

        --============================== Baud Generator ======================================
        Baud_Generator_RX : process(clk, reset)
            begin
            -- Reset the baud Generator
            if(reset = '1') then
                counter_RX <= 0;
                tmp_RX <= '0';
                reception_init <= 0;

            -- Baud generator creates a one clock pulse at every baud rate interval
            elsif (rising_edge(clk)) then
                if (Receive_current_state /= idle) then
                    if (counter_RX = max_counter - 1) then
                        tmp_RX <= '1';
                        counter_RX <= 0;
                    else
                        counter_RX <= counter_RX + 1;
                        tmp_RX <= '0';
                    end if;

                -- Half baud generator for the first bit of reception. Done to centre acquisition of data bits
                -- Reception init gives a buffer to ensure glitchs on the RX line are not interpreted as data bits
                elsif (RX = '0' or reception_init > 0) then
                    if (counter_RX = integer(max_counter/2)-1) then
                        tmp_RX <= '1';
                        counter_RX <= 0;
                    else
                        counter_RX <= counter_RX + 1;
                        tmp_RX <= '0';
                        if (RX = '0') then
                            reception_init <= RX_Buffer_size;
                        else 
                            reception_init <= reception_init - 1;
                        end if;
                    end if;

                else 
                    counter_RX <= 0;
                    tmp_RX <= '0';
                end if;
            end if;
        end process;

        --===================== Receivers Logic =================================

        Reception_State_Transition : process (reset, RX, reception_bit_position, N_stop_bits_rx, Receive_current_state )
            begin
            if (reset = '1') then
                    Receive_next_state <= idle;
            else
                case Receive_current_state is

                    -- Idle state waits for the start bit to be received to start the reception
                    when idle =>
                        if (RX = '0') then
                            Receive_next_state <= start_bit;
                        else
                            Receive_next_state <= idle;
                        end if;
                        
                    -- Always goes to data bits. No conditions
                    when start_bit =>
                        Receive_next_state <= data_bits;

                    -- Cycles through the data bits until N_data is reached. Either goes to parity or stop bits depending on the parity settings
                    when data_bits =>
                        if (reception_bit_position = N_data) then
                            if (N_parity = 0) then
                                Receive_next_state <= stop_bits;
                            else
                                Receive_next_state <= parity_bits;
                            end if;
                        else
                            Receive_next_state <= data_bits;
                        end if;

                    -- Always goes to stop bits. No conditions
                    when parity_bits =>
                        Receive_next_state <= stop_bits;

                    -- Cycles through the stop bits until N_stop is reached. Either goes back to idle or stop bits depending on the number of stop bits selected
                    when stop_bits =>
                        if (N_stop_bits_rx = N_stop) then
                            Receive_next_state <= idle;
                        else
                            Receive_next_state <= stop_bits;
                        end if;
                end case;
            end if;
        end process;

        Reception_Input : process(clk, reset)
            begin
            if (reset = '1') then
                data_received <= (others => '0');
                reception_bit_position <= 0;
                N_stop_bits_rx <= 0;
                Error_buffer <= '0';
                Error <= '0';
                parity_RX <= '0';
                Receive_current_state <= idle;

            elsif (rising_edge(clk)) then
                    
                if (tmp_RX = '1') then
                    Receive_current_state <= Receive_next_state;

                    case Receive_next_state is 

                        -- Idle state resets the reception variables
                        when idle =>
                            data_received <= (others => '0');
                            reception_bit_position <= 0;
                            N_stop_bits_rx <= 0;
                            Error_buffer <= '0';
                            parity_RX <= '0';
                            Error <= Error_buffer;
                        
                        -- Start bit see if the start bit is valid
                        when start_bit =>
                            if (RX /= '0') then
                                Error_buffer <= '1';
                            else
                                Error_buffer <= '0';
                            end if;
                                
                        -- Data bits receives the data bits one by one until N_data is reached. Also calculates the parity.
                        when data_bits =>
                            data_received(reception_bit_position) <= RX;
                            parity_RX <= parity_RX xor RX;
                            reception_bit_position <= reception_bit_position + 1;

                        -- Receives the parity bit depending on the parity type selected in the generic
                        when parity_bits =>
                            if (Parity_type = '0') then     -- If odd parity was selected
                                if (RX /= parity_RX) then
                                    Error_buffer <= Error_buffer or '1';
                                else
                                    Error_buffer <= Error_buffer or '0';
                                end if;
                            else                            -- If even parity was selected
                                if (RX = parity_RX) then
                                    Error_buffer <= Error_buffer or '1';
                                else
                                    Error_buffer <= Error_buffer or '0';
                                end if;
                            end if;

                        -- Receives the stop bits depending on the number of stop bits selected in the generic. Also checks for framing errors
                        -- Asserts the error signal
                        when stop_bits =>
                            N_stop_bits_rx <= N_stop_bits_rx + 1;
                            if (RX = '1') then
                                Error_buffer <= Error_buffer or '0';
                                Error <= Error_buffer;
                            else
                                Error_buffer <= Error_buffer or '1';
                                Error <= Error_buffer;
                            end if;
                            
                    end case;
                else 
                    null;
                end if;
            end if;
        end process;
    end architecture;