#!/usr/bin/env python3
"""
Serial bridge for SMART-TRAP Flutter app.
Communicates with ESP32 via serial port and relays commands/responses
via stdin/stdout to the Flutter app.

Protocol (stdin -> this script):
  SCAN           - Scan for available ports
  OPEN:<port>    - Open a specific port
  SEND:<data>    - Send data to the open port
  READ:<timeout> - Read a line (timeout in ms)
  CLOSE          - Close the port
  QUIT           - Exit

Protocol (this script -> stdout):
  OK:<data>      - Success response
  ERR:<message>  - Error response
  PORTS:<json>   - List of available ports
"""

import sys
import os
import glob
import json
import time
import struct
import fcntl
import termios
import select

# Global state
serial_fd = None
read_buffer = b""


def find_serial_ports():
    """Find available serial ports."""
    ports = []
    for pattern in ["/dev/ttyUSB*", "/dev/ttyACM*"]:
        ports.extend(glob.glob(pattern))
    return sorted(ports)


def configure_port(fd, baudrate=115200):
    """Configure serial port using termios."""
    attrs = termios.tcgetattr(fd)
    
    # Input flags - Turn off input processing
    attrs[0] = 0  # iflag
    
    # Output flags - Turn off output processing
    attrs[1] = 0  # oflag
    
    # Control flags
    attrs[2] = termios.CS8 | termios.CLOCAL | termios.CREAD
    
    # Local flags - Turn off canonical mode, echo, etc.
    attrs[3] = 0  # lflag
    
    # Set baud rate
    speed_map = {
        9600: termios.B9600,
        19200: termios.B19200,
        38400: termios.B38400,
        57600: termios.B57600,
        115200: termios.B115200,
    }
    speed = speed_map.get(baudrate, termios.B115200)
    attrs[4] = speed  # ispeed
    attrs[5] = speed  # ospeed
    
    # cc - special characters
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 1  # 0.1 second timeout
    
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)


def try_usb_reset(port_path):
    """Try to reset the USB device associated with a serial port."""
    try:
        # Find the USB device path from sysfs
        # /dev/ttyUSB1 -> /sys/class/tty/ttyUSB1/device -> follow symlinks to USB device
        tty_name = os.path.basename(port_path)
        sysfs_path = f"/sys/class/tty/{tty_name}/device"
        
        if not os.path.exists(sysfs_path):
            return False, f"No sysfs path for {tty_name}"
        
        # Walk up to find the USB device
        real_path = os.path.realpath(sysfs_path)
        # Go up directories until we find one with 'busnum' and 'devnum'
        current = real_path
        usb_dev_path = None
        for _ in range(10):
            if os.path.exists(os.path.join(current, "busnum")) and os.path.exists(os.path.join(current, "devnum")):
                usb_dev_path = current
                break
            current = os.path.dirname(current)
        
        if usb_dev_path is None:
            return False, "Could not find USB device in sysfs"
        
        # Try ioctl USBDEVFS_RESET (doesn't require root if user has device permissions)
        busnum = int(open(os.path.join(usb_dev_path, "busnum")).read().strip())
        devnum = int(open(os.path.join(usb_dev_path, "devnum")).read().strip())
        usb_dev_file = f"/dev/bus/usb/{busnum:03d}/{devnum:03d}"
        
        if os.path.exists(usb_dev_file):
            USBDEVFS_RESET = 21780  # _IO('U', 20)
            try:
                fd = os.open(usb_dev_file, os.O_WRONLY)
                fcntl.ioctl(fd, USBDEVFS_RESET, 0)
                os.close(fd)
                time.sleep(2)  # Wait for device to re-enumerate
                return True, f"USB reset via {usb_dev_file}"
            except Exception as e:
                return False, f"ioctl reset failed: {e}"
        
        return False, f"USB device file not found: {usb_dev_file}"
    except Exception as e:
        return False, f"USB reset error: {e}"


def reset_esp32(fd):
    """Reliably reset ESP32 into application mode by manipulating DTR and RTS."""
    try:
        # Constants for ioctl
        TIOCMBIC = 0x5417
        TIOCMBIS = 0x5416
        TIOCM_DTR = 0x002
        TIOCM_RTS = 0x004
        
        # 1. Reset (EN=0, IO0=1)
        # DTR=False (0), RTS=True (1)
        fcntl.ioctl(fd, TIOCMBIC, struct.pack('I', TIOCM_DTR))
        fcntl.ioctl(fd, TIOCMBIS, struct.pack('I', TIOCM_RTS))
        time.sleep(0.1)
        
        # 2. Normal run (EN=1, IO0=1)
        # DTR=False (0), RTS=False (0)
        fcntl.ioctl(fd, TIOCMBIC, struct.pack('I', TIOCM_DTR | TIOCM_RTS))
        time.sleep(0.5) # Wait a bit for boot to start
    except Exception as e:
        pass


def try_open_port(port_path, max_retries=5, retry_delay=1.0):
    """Try to open a serial port with retries and USB reset fallback."""
    global serial_fd
    
    for attempt in range(max_retries):
        try:
            fd = os.open(port_path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
            # Clear the O_NONBLOCK flag after opening
            flags = fcntl.fcntl(fd, fcntl.F_GETFL)
            fcntl.fcntl(fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
            
            configure_port(fd)
            reset_esp32(fd)
            serial_fd = fd
            return True, f"Opened successfully (attempt {attempt + 1})"
        except OSError as e:
            if e.errno == 16:  # EBUSY
                if attempt == 1:
                    # Try USB device reset on second attempt
                    respond(f"OK:DIAG:Port busy, attempting USB reset...")
                    success, msg = try_usb_reset(port_path)
                    respond(f"OK:DIAG:USB reset result: {success} - {msg}")
                    if success:
                        time.sleep(2)
                        # After USB reset, the port may have a new name
                        new_ports = find_serial_ports()
                        respond(f"OK:DIAG:After reset, available ports: {new_ports}")
                        if new_ports:
                            # Try the first available port (it's likely the re-enumerated device)
                            port_path = new_ports[0]
                            respond(f"OK:DIAG:Switching to port {port_path}")
                        continue
                if attempt < max_retries - 1:
                    respond(f"OK:DIAG:Port busy (attempt {attempt + 1}/{max_retries}), retrying in {retry_delay}s...")
                    time.sleep(retry_delay)
                    continue
            elif e.errno == 2:  # ENOENT
                # Port disappeared (maybe after USB reset re-enumeration)
                new_ports = find_serial_ports()
                if new_ports and attempt < max_retries - 1:
                    port_path = new_ports[0]
                    respond(f"OK:DIAG:Port vanished, switching to {port_path}")
                    time.sleep(1)
                    continue
                return False, f"Port {port_path} does not exist (errno=2)"
            elif e.errno == 13:  # EACCES
                return False, f"Permission denied on {port_path} (errno=13). Run: sudo chmod 666 {port_path}"
            return False, f"errno={e.errno}: {os.strerror(e.errno)}"
    
    return False, "Max retries exceeded (EBUSY)"


def write_to_port(data):
    """Write data to the serial port."""
    global serial_fd
    if serial_fd is None:
        return False, "Port not open"
    try:
        os.write(serial_fd, data.encode('utf-8'))
        return True, "OK"
    except Exception as e:
        return False, str(e)


def read_line(timeout_ms=3000):
    """Read a line from the serial port with timeout."""
    global serial_fd, read_buffer
    if serial_fd is None:
        return False, "Port not open"
    
    deadline = time.time() + (timeout_ms / 1000.0)
    
    while time.time() < deadline:
        # Check if we already have a complete line
        if b'\n' in read_buffer:
            idx = read_buffer.index(b'\n')
            line = read_buffer[:idx].decode('utf-8', errors='replace').strip()
            read_buffer = read_buffer[idx + 1:]
            return True, line
        
        # Wait for data
        remaining = deadline - time.time()
        if remaining <= 0:
            break
            
        ready, _, _ = select.select([serial_fd], [], [], min(remaining, 0.1))
        if ready:
            try:
                chunk = os.read(serial_fd, 1024)
                if chunk:
                    read_buffer += chunk
            except OSError:
                break
    
    return False, "Timeout"


def close_port():
    """Close the serial port."""
    global serial_fd, read_buffer
    if serial_fd is not None:
        try:
            os.close(serial_fd)
        except:
            pass
        serial_fd = None
    read_buffer = b""


def respond(msg):
    """Send response to stdout."""
    print(msg, flush=True)


def main():
    # Unbuffer stdout
    sys.stdout.reconfigure(line_buffering=True)
    
    respond("OK:READY")
    
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        
        if line == "SCAN":
            ports = find_serial_ports()
            respond(f"PORTS:{json.dumps(ports)}")
        
        elif line.startswith("OPEN:"):
            port_path = line[5:]
            close_port()  # Close any existing connection
            success, msg = try_open_port(port_path)
            if success:
                respond(f"OK:{msg}")
            else:
                respond(f"ERR:{msg}")
        
        elif line.startswith("SEND:"):
            data = line[5:]
            success, msg = write_to_port(data + "\n")
            if success:
                respond(f"OK:sent")
            else:
                respond(f"ERR:{msg}")
        
        elif line.startswith("READ:"):
            timeout_ms = int(line[5:])
            success, msg = read_line(timeout_ms)
            if success:
                respond(f"OK:{msg}")
            else:
                respond(f"ERR:{msg}")
        
        elif line == "CLOSE":
            close_port()
            respond("OK:closed")
        
        elif line == "QUIT":
            close_port()
            respond("OK:bye")
            break
        
        else:
            respond(f"ERR:Unknown command: {line}")
    
    close_port()


if __name__ == "__main__":
    main()
