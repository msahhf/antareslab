"""
AntaresStudio IoT - ESP32 Auto-Discovery & Registration v3.1

Zero-configuration backend IP registration with ESP32-CAM.

Features:
  [1] Auto-detect PC IP on ESP32 subnet (192.168.4.x)
  [2] Register with ESP32 on backend startup
  [3] Periodic re-registration (in case ESP32 reboots)
  [4] Fallback to common IPs if auto-detection fails
"""

import asyncio
import socket
import struct
import logging
import platform
from typing import Optional, List
from dataclasses import dataclass
import httpx

logger = logging.getLogger("antares.discovery")

# ESP32 default AP IP
ESP32_DEFAULT_IP = "192.168.4.1"
ESP32_CONFIG_ENDPOINT = "/api/config/backend-ip"

# Common PC IPs to try if auto-detection fails (in order)
FALLBACK_IPS = [
    "192.168.4.2",
    "192.168.4.100",
    "192.168.4.101",
    "192.168.4.50",
]


@dataclass
class NetworkInterface:
    """Network interface information."""
    name: str
    ip_address: str
    netmask: str
    is_wifi: bool


def get_network_interfaces() -> List[NetworkInterface]:
    """
    Get all network interfaces with their IP addresses.
    
    Returns list of interfaces with IP, netmask, and type.
    """
    interfaces = []
    
    try:
        # Method 1: Using socket and netifaces if available
        try:
            import netifaces
            
            for iface_name in netifaces.interfaces():
                addrs = netifaces.ifaddresses(iface_name)
                
                # Get IPv4 addresses
                if netifaces.AF_INET in addrs:
                    for addr_info in addrs[netifaces.AF_INET]:
                        ip = addr_info.get('addr')
                        netmask = addr_info.get('netmask', '255.255.255.0')
                        
                        if ip and not ip.startswith('127.'):
                            is_wifi = 'wi' in iface_name.lower() or 'wlan' in iface_name.lower()
                            interfaces.append(NetworkInterface(
                                name=iface_name,
                                ip_address=ip,
                                netmask=netmask,
                                is_wifi=is_wifi
                            ))
            
            return interfaces
            
        except ImportError:
            pass  # Fall through to alternative method
        
        # Method 2: Using socket (works on Windows/Linux/Mac)
        hostname = socket.gethostname()
        all_ips = socket.getaddrinfo(hostname, None, socket.AF_INET)
        
        seen_ips = set()
        for ip_info in all_ips:
            ip = ip_info[4][0]
            if ip not in seen_ips and not ip.startswith('127.'):
                seen_ips.add(ip)
                interfaces.append(NetworkInterface(
                    name="unknown",
                    ip_address=ip,
                    netmask="255.255.255.0",
                    is_wifi=False
                ))
        
        # Method 3: Windows-specific using ipconfig (fallback)
        if platform.system() == "Windows" and not interfaces:
            interfaces = _get_windows_interfaces()
        
    except Exception as e:
        logger.warning(f"Error detecting network interfaces: {e}")
    
    return interfaces


def _get_windows_interfaces() -> List[NetworkInterface]:
    """Windows-specific interface detection using subprocess."""
    import subprocess
    import re
    
    interfaces = []
    
    try:
        result = subprocess.run(['ipconfig'], capture_output=True, text=True)
        output = result.stdout
        
        # Parse IPv4 addresses from ipconfig output
        ipv4_pattern = r'IPv4 Address[^:]*:\s*(\d+\.\d+\.\d+\.\d+)'
        subnet_pattern = r'Subnet Mask[^:]*:\s*(\d+\.\d+\.\d+\.\d+)'
        
        ipv4_matches = re.findall(ipv4_pattern, output)
        
        for ip in ipv4_matches:
            if not ip.startswith('127.'):
                interfaces.append(NetworkInterface(
                    name="windows_adapter",
                    ip_address=ip,
                    netmask="255.255.255.0",
                    is_wifi="Wi-Fi" in output
                ))
    
    except Exception as e:
        logger.warning(f"Windows interface detection failed: {e}")
    
    return interfaces


def is_same_subnet(ip1: str, ip2: str, netmask: str = "255.255.255.0") -> bool:
    """Check if two IPs are on the same subnet."""
    try:
        ip1_int = struct.unpack('!I', socket.inet_aton(ip1))[0]
        ip2_int = struct.unpack('!I', socket.inet_aton(ip2))[0]
        mask_int = struct.unpack('!I', socket.inet_aton(netmask))[0]
        
        return (ip1_int & mask_int) == (ip2_int & mask_int)
    except:
        return False


def find_esp32_subnet_ip() -> Optional[str]:
    """
    Find the PC's IP address on the ESP32's subnet (192.168.4.x).
    
    Returns the IP address, or None if not found.
    """
    interfaces = get_network_interfaces()
    
    logger.debug(f"Found {len(interfaces)} network interfaces")
    
    for iface in interfaces:
        logger.debug(f"Interface: {iface.name} - {iface.ip_address}/{iface.netmask}")
        
        # Check if this interface is on ESP32 subnet (192.168.4.x)
        if iface.ip_address.startswith("192.168.4."):
            logger.info(f"Found ESP32 subnet interface: {iface.ip_address} on {iface.name}")
            return iface.ip_address
    
    # If no 192.168.4.x interface found, try to find any interface
    # that might route to ESP32
    for iface in interfaces:
        # Prefer WiFi interfaces
        if iface.is_wifi and not iface.ip_address.startswith("127."):
            logger.info(f"Using WiFi interface: {iface.ip_address}")
            return iface.ip_address
    
    # Last resort: any non-loopback IP
    for iface in interfaces:
        if not iface.ip_address.startswith("127."):
            logger.info(f"Using interface: {iface.ip_address}")
            return iface.ip_address
    
    return None


async def register_with_esp32(
    backend_ip: str,
    port: int = 8000,
    esp32_ip: str = ESP32_DEFAULT_IP,
    max_retries: int = 5,
    retry_delay: float = 2.0
) -> bool:
    """
    Register the backend IP with ESP32.
    
    Args:
        backend_ip: The PC's IP address to register
        port: The backend port
        esp32_ip: The ESP32's IP address (default: 192.168.4.1)
        max_retries: Number of retry attempts
        retry_delay: Seconds between retries
    
    Returns:
        True if registration successful, False otherwise
    """
    url = f"http://{esp32_ip}{ESP32_CONFIG_ENDPOINT}"
    
    payload = {
        "ip": backend_ip,
        "port": port,
        "hostname": socket.gethostname(),
        "version": "3.1.0"
    }
    
    logger.info(f"Registering backend {backend_ip}:{port} with ESP32 at {esp32_ip}...")
    
    for attempt in range(max_retries):
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.post(url, json=payload)
                
                if response.status_code == 200:
                    data = response.json()
                    if data.get("ok"):
                        stored_ip = data.get("stored_ip", "unknown")
                        logger.info(f"✅ Successfully registered backend IP ({backend_ip}) to ESP32!")
                        logger.info(f"   ESP32 confirmed: {stored_ip}")
                        return True
                    else:
                        logger.warning(f"ESP32 rejected registration: {data}")
                else:
                    logger.warning(f"Registration failed (HTTP {response.status_code}): {response.text}")
        
        except httpx.ConnectError:
            logger.debug(f"Attempt {attempt + 1}/{max_retries}: ESP32 not reachable at {esp32_ip}")
        except Exception as e:
            logger.debug(f"Attempt {attempt + 1}/{max_retries}: {e}")
        
        if attempt < max_retries - 1:
            await asyncio.sleep(retry_delay)
    
    logger.warning(f"❌ Failed to register with ESP32 after {max_retries} attempts")
    logger.warning(f"   ESP32 may not be connected, or PC is not on ANTARES_KAPSUL_LAB network")
    return False


async def try_fallback_registrations(port: int = 8000) -> Optional[str]:
    """
    Try registering with common fallback IPs if auto-detection fails.
    
    Returns the working IP if successful, None otherwise.
    """
    logger.info("Trying fallback IP registrations...")
    
    for ip in FALLBACK_IPS:
        logger.debug(f"Trying fallback IP: {ip}")
        
        if await register_with_esp32(ip, port, max_retries=2, retry_delay=1.0):
            return ip
    
    return None


async def startup_registration_task(port: int = 8000) -> Optional[str]:
    """
    Complete startup registration workflow.
    
    1. Auto-detect PC IP on ESP32 subnet
    2. Try to register with ESP32
    3. Fall back to common IPs if needed
    
    Returns the registered IP address, or None if failed.
    """
    logger.info("=" * 60)
    logger.info("Starting ESP32 Auto-Discovery...")
    logger.info("=" * 60)
    
    # Step 1: Auto-detect IP
    detected_ip = find_esp32_subnet_ip()
    
    if detected_ip:
        logger.info(f"Detected PC IP: {detected_ip}")
        
        # Step 2: Try to register
        if await register_with_esp32(detected_ip, port):
            return detected_ip
        
        logger.warning("Auto-detected IP registration failed, trying fallbacks...")
    else:
        logger.warning("Could not auto-detect IP on ESP32 subnet (192.168.4.x)")
        logger.info("Make sure you're connected to Wi-Fi: ANTARES_KAPSUL_LAB")
    
    # Step 3: Try fallbacks
    fallback_ip = await try_fallback_registrations(port)
    
    if fallback_ip:
        logger.info(f"✅ Fallback registration successful with IP: {fallback_ip}")
        return fallback_ip
    
    logger.error("❌ All registration attempts failed!")
    logger.error("   ESP32 uploads will use default IP (may not work)")
    
    return None


async def periodic_reregistration_task(
    registered_ip: str,
    port: int = 8000,
    interval_seconds: float = 60.0
):
    """
    Background task to periodically re-register with ESP32.
    
    This handles cases where ESP32 reboots and loses the registration.
    """
    while True:
        await asyncio.sleep(interval_seconds)
        
        # Try to re-register
        success = await register_with_esp32(
            registered_ip,
            port,
            max_retries=2,
            retry_delay=1.0
        )
        
        if not success:
            logger.debug("Periodic re-registration failed, will retry next cycle")


def get_local_ip_manual() -> str:
    """
    Fallback method: Get local IP by connecting to a remote address.
    Works even without internet by using a dummy address.
    """
    try:
        # Create a UDP socket
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        
        # Try to connect to a dummy address (doesn't actually send packets)
        s.connect(("10.255.255.255", 1))
        
        # Get the local IP used for this connection
        ip = s.getsockname()[0]
        s.close()
        
        return ip
    except:
        return "127.0.0.1"


# Global state
_registered_ip: Optional[str] = None

async def run_discovery_and_registration(port: int = 8000) -> Optional[str]:
    """
    Main entry point for discovery and registration.
    
    Call this from main.py lifespan startup.
    """
    global _registered_ip
    
    _registered_ip = await startup_registration_task(port)
    
    if _registered_ip:
        # Start periodic re-registration in background
        asyncio.create_task(periodic_reregistration_task(_registered_ip, port))
    
    return _registered_ip


def get_registered_ip() -> Optional[str]:
    """Get the currently registered IP address."""
    return _registered_ip
