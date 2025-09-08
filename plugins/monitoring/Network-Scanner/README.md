# Network Scanner Plugin

A comprehensive network discovery and scanning plugin for NinjaSuite, based on the excellent [illsk1lls/IPScanner](https://github.com/illsk1lls/IPScanner) project.

## Features

### 🔍 **Network Discovery**
- **Subnet Scanning**: Configurable CIDR notation support (e.g., 192.168.1.0/24)
- **Device Detection**: Automatically discovers active devices on your network
- **Fast Scanning**: Multi-threaded ping operations with configurable concurrency
- **Hostname Resolution**: Resolves device hostnames when available

### 📊 **Device Information**
- **MAC Address Resolution**: Retrieves MAC addresses from ARP table
- **Vendor Identification**: Identifies device manufacturers from MAC OUI
- **Device Type Detection**: Intelligent device categorization (Router, Printer, etc.)
- **Response Time Monitoring**: Tracks ping response times

### 🔒 **Port Scanning**
- **Common Port Detection**: Scans for commonly used ports
- **Service Identification**: Identifies services running on open ports
- **Configurable Port Lists**: Customize which ports to scan
- **Security Assessment**: Helps identify potential security risks

### 🎨 **Modern Interface**
- **Professional UI**: Modern WPF interface with theme support
- **Real-time Results**: Live updates during scanning process
- **Interactive Details**: Click devices for detailed information
- **Visual Status Indicators**: Color-coded online/offline status

### 📈 **Export Capabilities**
- **Multiple Formats**: Export to HTML, CSV, JSON, and XML
- **Professional Reports**: Styled HTML reports with statistics
- **Data Analysis**: Structured data for further analysis
- **Audit Trail**: Historical scan documentation

## Usage

### Basic Scanning
1. **Enter Subnet**: Specify the network range to scan (e.g., `192.168.1.0/24`)
2. **Configure Options**: Enable/disable port scanning as needed
3. **Start Scan**: Click "Start Scan" to begin discovery
4. **View Results**: Devices appear in the list as they're discovered

### Device Details
- **Select Device**: Click any device in the list to view detailed information
- **Port Information**: View open ports and running services
- **Device Actions**: Access ping, port scan, and remote connection options

### Export Results
- **Export Button**: Click the export button to save scan results
- **Format Selection**: Choose from HTML, CSV, JSON, or XML formats
- **Professional Reports**: HTML exports include styling and statistics

## Configuration

### Settings Options
- **Default Subnet**: Set your preferred network range
- **Scan Timeout**: Configure ping timeout (100-10000ms)
- **Concurrent Scans**: Adjust simultaneous operations (1-200)
- **Port Scanning**: Enable/disable port detection
- **Common Ports**: Customize which ports to scan
- **Auto Refresh**: Automatic scan repetition

### Performance Tuning
- **Lower concurrency** for slower networks or systems
- **Increase timeout** for networks with high latency
- **Disable port scanning** for faster basic discovery
- **Adjust refresh interval** for monitoring scenarios

## Security Considerations

### Permissions Required
- **Network Access**: Required for ping and port scanning operations
- **Device Read**: Needed for ARP table access and hostname resolution
- **Monitoring Access**: For continuous network monitoring features

### Ethical Use
- **Network Ownership**: Only scan networks you own or have permission to test
- **Rate Limiting**: Built-in throttling prevents network flooding
- **Non-Intrusive**: Uses standard network protocols (ICMP, TCP)
- **No Exploitation**: Discovery only, no vulnerability exploitation

## Technical Details

### Network Protocols
- **ICMP Ping**: Primary discovery method for device detection
- **ARP Resolution**: MAC address and vendor identification
- **TCP Connect**: Port scanning for service discovery
- **DNS Lookup**: Hostname resolution when available

### Device Detection Logic
- **Response Analysis**: Ping response indicates active device
- **MAC Resolution**: ARP table lookup for physical addresses
- **Vendor Mapping**: OUI database for manufacturer identification
- **Service Detection**: Port-based service identification

### Performance Characteristics
- **Concurrent Operations**: Configurable threading for optimal performance
- **Memory Efficient**: Minimal memory footprint during scanning
- **Network Friendly**: Respects network resources with throttling
- **Responsive UI**: Non-blocking interface during scan operations

## Based On

This plugin is inspired by and based on the [illsk1lls/IPScanner](https://github.com/illsk1lls/IPScanner) project, which provides:

- Fast network scanning capabilities
- Professional HTML export formatting  
- Efficient multi-threading implementation
- Cross-platform PowerShell compatibility

## License

MIT License - Same as the original IPScanner project

## Support

For support with this plugin:
- Check the NinjaSuite documentation
- Review the original [IPScanner repository](https://github.com/illsk1lls/IPScanner)
- Submit issues through the NinjaSuite support channels

---

**⚠️ Important**: Always ensure you have proper authorization before scanning networks. This tool should only be used on networks you own or have explicit permission to test.
