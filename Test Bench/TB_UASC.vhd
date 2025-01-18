library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all; 

entity TB_UART is
end entity TB_UART;

architecture tb of TB_UART is

    constant TB_CLOCK_FREQ  : integer := 10_000_000; -- 10 MHz
    constant TB_BAUD        : integer := 115_200;        
    constant TB_N_DATA      : integer := 8;          -- 8 data bits
    constant TB_N_STOP      : integer := 1;          -- 1 stop bit
    constant TB_N_PARITY    : integer := 1;          -- 1 => parity enabled
    constant TB_PARITY_TYPE : std_logic := '0';      -- '0' => odd parity, '1' => even

    signal clk           : std_logic := '0';
    signal reset         : std_logic := '0';

    signal data_to_send  : std_logic_vector(TB_N_DATA-1 downto 0) := (others => '0');
    signal data_received : std_logic_vector(TB_N_DATA-1 downto 0);
    signal send_data     : std_logic := '0';
    signal Error         : std_logic;

    -- UART lines
    signal RX            : std_logic;
    signal TX            : std_logic;
    
begin

    ----------------------------------------------------------------------------
    --  Instantiate the UART
    ----------------------------------------------------------------------------
    UUT_UART : entity work.UART
        generic map (
            N_data      => TB_N_DATA,
            N_parity    => TB_N_PARITY,
            N_stop      => TB_N_STOP,
            Parity_type => TB_PARITY_TYPE,
            CLOCKFREQ   => TB_CLOCK_FREQ,
            Baud        => TB_BAUD
        )
        port map (
            clk            => clk,
            reset          => reset,
            data_to_send   => data_to_send,
            data_received  => data_received,
            send_data      => send_data,
            Error          => Error,
            RX             => RX,
            TX             => TX
        );
        
    -- LOOPBACK
    RX <= TX;


    ClockGen : process
    begin
        while true loop
            clk <= '0';
            wait for 50 ns;
            clk <= '1';
            wait for 50 ns;
        end loop;
    end process;

    ----------------------------------------------------------------------------
    -- Main Test Process
    ----------------------------------------------------------------------------
    Test_Sequence : process
        -- A little function for more compact Hex/Bin conversions in the test
        function to_slv8(val : integer) return std_logic_vector is
            variable tmp : std_logic_vector(7 downto 0);
        begin
            tmp := std_logic_vector(to_unsigned(val, 8));
            return tmp;
        end;
    begin
        report "==== Starting Test Bench ====" severity note;

        --========================================================
        -- 1) Global Reset
        --========================================================
        report "==== Test #1: Reset Initialization ====" severity note;
        reset <= '1';
        wait for 200 ns;  -- hold reset for a few clock cycles
        reset <= '0';
        wait for 200 ns;
        report "      Check that module is in idle, signals cleared" severity note;

        --========================================================
        -- 2) Basic Transmission: Send a single byte (0x55)
        --========================================================
        report "==== Test #2: Send a single byte (0x55) ====" severity note;
        data_to_send <= "01010101";  -- 0x55
        send_data    <= '1';
        wait for 200000 ns;  -- Wait long enough for entire transmission
        send_data    <= '0';

        wait for 100000 ns;  -- Let the loopback data be fully received
        report "      Check data_received for 0x55" severity note;

        --========================================================
        -- 3) Send Another Byte (0xAA)
        --========================================================
        report "==== Test #3: Send another byte (0xAA) ====" severity note;
        data_to_send <= "10101010";  -- 0xAA
        send_data    <= '1';
        wait for 200000 ns;
        send_data    <= '0';

        wait for 100000 ns;
        report "      Check data_received for 0xAA" severity note;

        --========================================================
        -- 4) Reset in the Middle of a Transmission
        --========================================================
        report "==== Test #4: Assert Reset During Transmission ====" severity note;
        data_to_send <= "11111111";  -- 0xFF
        send_data    <= '1';
        wait for 100000 ns;  -- Wait partway into sending
        reset <= '1';
        wait for 200 ns;
        reset <= '0';
        send_data <= '0';  -- Deassert send_data after reset
        wait for 200000 ns; 
        report "      Check that the design recovers to idle" severity note;

        --========================================================
        -- 5) Multiple Consecutive Bytes
        --========================================================
        report "==== Test #5: Multiple Consecutive Bytes ====" severity note;
        for i in 0 to 5 loop
            data_to_send <= to_slv8(i*16 + i);  -- Some pattern
            send_data    <= '1';
            wait for 80000 ns;  -- Shorter wait between sends
            send_data    <= '0';

            -- Wait enough time for the byte + stop bits to finish
            -- The exact value depends on your baud & data config
            wait for 200000 ns; 
            report "      Sent byte " & integer'image(i*16 + i) severity note;
        end loop;
        wait for 500000 ns;  -- wait to ensure final receptions are done

        --========================================================
        -- 6) Special Patterns: 0x00 and 0xFF
        --========================================================
        report "==== Test #6: Send 0x00 and 0xFF patterns ====" severity note;
        -- Send 0x00
        data_to_send <= (others => '0');
        send_data <= '1';
        wait for 200000 ns;
        send_data <= '0';
        wait for 200000 ns;
        report "      Check data_received for 0x00" severity note;

        -- Send 0xFF
        data_to_send <= (others => '1');
        send_data <= '1';
        wait for 200000 ns;
        send_data <= '0';
        wait for 200000 ns;
        report "      Check data_received for 0xFF" severity note;

        --========================================================
        -- 7) Simple "Stress" Test: Rapid Fire in a Tight Loop
        --========================================================
        report "==== Test #7: Rapid-Fire Transmission ====" severity note;
        for j in 0 to 9 loop
            data_to_send <= to_slv8(j + 32); -- Send ASCII-like range
            send_data    <= '1';
            wait for 70000 ns;  -- fairly short interval
            send_data    <= '0';
            wait for 130000 ns; -- let each byte finish
        end loop;
        wait for 1 ms;

        --========================================================
        -- 8) End of Tests
        --========================================================
        report "==== All Tests Completed ====" severity note;
        wait;
    end process;

end architecture tb;