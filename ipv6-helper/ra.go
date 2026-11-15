package main

import (
	"encoding/binary"
	"fmt"
	"net"
	"net/netip"
	"os"
	"strconv"
	"syscall"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 2 && args[0] == "prefix" {
		prefix, err := netip.ParsePrefix(args[1])
		if err != nil || prefix.Bits() != 64 || !prefix.Addr().Is6() {
			return fmt.Errorf("invalid IPv6 /64 address")
		}
		fmt.Println(prefix.Masked())
		return nil
	}
	return advertise(args)
}

func advertise(args []string) error {
	if len(args) != 4 {
		return fmt.Errorf("usage: ra interface client-mac prefix lifetime")
	}
	iface, err := net.InterfaceByName(args[0])
	if err != nil {
		return err
	}
	client, err := net.ParseMAC(args[1])
	if err != nil || len(client) != 6 || client[0]&1 != 0 {
		return fmt.Errorf("invalid client MAC")
	}
	prefix, err := netip.ParsePrefix(args[2])
	if err != nil || prefix.Bits() != 64 || !prefix.Addr().Is6() {
		return fmt.Errorf("invalid IPv6 prefix")
	}
	lifetime, err := strconv.ParseUint(args[3], 10, 16)
	if err != nil || lifetime > 120 {
		return fmt.Errorf("invalid router lifetime")
	}
	addresses, err := iface.Addrs()
	if err != nil {
		return err
	}
	var source netip.Addr
	for _, address := range addresses {
		parsed, err := netip.ParsePrefix(address.String())
		if err == nil && parsed.Addr().IsLinkLocalUnicast() {
			source = parsed.Addr()
			break
		}
	}
	if !source.IsValid() || len(iface.HardwareAddr) != 6 {
		return fmt.Errorf("no Ethernet and link-local address on %s", iface.Name)
	}

	// Send the advertisement only to the configured client's Ethernet address.
	destination := netip.MustParseAddr("ff02::1")
	payload := make([]byte, 56)
	payload[0], payload[4] = 134, 64
	binary.BigEndian.PutUint16(payload[6:8], uint16(lifetime))
	payload[16], payload[17] = 1, 1
	copy(payload[18:24], iface.HardwareAddr)
	payload[24], payload[25], payload[26], payload[27] = 3, 4, 64, 0x40
	binary.BigEndian.PutUint32(payload[28:32], uint32(lifetime)*2)
	binary.BigEndian.PutUint32(payload[32:36], uint32(lifetime))
	copy(payload[40:56], prefix.Masked().Addr().AsSlice())
	binary.BigEndian.PutUint16(payload[2:4], checksum(source, destination, payload))

	frame := make([]byte, 14+40+len(payload))
	copy(frame[0:6], client)
	copy(frame[6:12], iface.HardwareAddr)
	binary.BigEndian.PutUint16(frame[12:14], 0x86dd)
	frame[14] = 0x60
	binary.BigEndian.PutUint16(frame[18:20], uint16(len(payload)))
	frame[20], frame[21] = 58, 255
	copy(frame[22:38], source.AsSlice())
	copy(frame[38:54], destination.AsSlice())
	copy(frame[54:], payload)

	fd, err := syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW, 0)
	if err != nil {
		return err
	}
	defer syscall.Close(fd)
	link := syscall.SockaddrLinklayer{Ifindex: iface.Index, Halen: 6, Protocol: 0xdd86}
	copy(link.Addr[:], client)
	return syscall.Sendto(fd, frame, 0, &link)
}

func checksum(source, destination netip.Addr, payload []byte) uint16 {
	sum := uint32(len(payload)) + 58
	for _, bytes := range [][]byte{source.AsSlice(), destination.AsSlice(), payload} {
		for i := 0; i < len(bytes); i += 2 {
			sum += uint32(binary.BigEndian.Uint16(bytes[i : i+2]))
		}
	}
	for sum > 0xffff {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	return ^uint16(sum)
}
