# UART (Universal Asynchronous Receiver/Transmitter)

**Author:** Jean-Stephane Cote  
**Date:** 2025-01-05  
**Version:** 1.0  

This VHDL module implements a simple, full-duplex UART. It does not perform oversampling, but instead samples each bit at the baud rate you specify.

## Features
- Configurable data width (N_data = 5 to 9 bits)
- Optional parity (no parity or 1 parity bit, which can be odd or even)
- 1 or 2 stop bits
- Baud rates up to 1,500,000. (Note. for the module to work properly, the clock must be at least 50 times the baud rate. Idealy 100 times the baud rate)
- Basic error detection for parity and framing


## Generic Parameters
| Parameter     | Type      | Default |   Range   | Description                                                 |
|---------------|-----------|---------|-----------|-------------------------------------------------------------|
| `N_data`      | integer   | 8       |   5 to 9  | Number of data bits                                         |
| `N_parity`    | integer   | 0       |   0 or 1  | Number of parity bits                                       |
| `Parity_type` | std_logic | 0       |   0 or 1  | Parity type. 0 = odd, 1 = even. If no parity, dont care     |
| `N_stop`      | integer   | 1       |   1 to 2  | Number of stop bits                                         |
| `CLOCKFREQ`   | integer   | 10e6    |    all    | Clock Frequency in Hz                                       |
| `Baud`        | integer   | 9600    |   9600 to 1 500 000  | Baud rate in bps                                 |

**Port Descriptions**
- `clk`: System clock input (rising edge).  
- `reset`: Active‐high reset.  
- `data_to_send`: Parallel data you want to transmit.  
- `data_received`: Parallel data received from the UART.  
- `send_data`: Pulse high to start sending `data_to_send`.  
- `Error`: High if a parity or framing error occurs.  
- `RX`: Serial data input (from external device).  
- `TX`: Serial data output (to external device).

**How It Works**
- **Transmit**:  
  The module latches `data_to_send` at the start bit, then sends each data bit in sequence. If parity is enabled, it sends the parity bit next, then the configured stop bits. The `data_to_send` signal must be asserted for the entire first baud tick period.
- **Receive**:  
  On detecting a low start bit, it samples bits at the baud rate. After collecting `N_data` bits (and parity if enabled), it checks stop bits to detect framing errors.

## Revision History
**v1.0 (2025-01-05)**  
- Initial release.  
