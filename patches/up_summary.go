package cmd

import (
	"context"
	"net"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/netbirdio/netbird/client/proto"
)

// printConnectionSummary prints, after "Connected", the DNS domain received
// from the management server and the IP address assigned to this peer.
// The daemon may need a moment to publish them, so poll briefly.
func printConnectionSummary(ctx context.Context, cmd *cobra.Command, client proto.DaemonServiceClient) {
	var ip, domain string
	for i := 0; i < 20; i++ {
		resp, err := client.Status(ctx, &proto.StatusRequest{GetFullPeerStatus: true})
		if err == nil {
			lp := resp.GetFullStatus().GetLocalPeerState()
			if addr, _, perr := net.ParseCIDR(lp.GetIP()); perr == nil {
				ip = addr.String()
			} else if a := net.ParseIP(lp.GetIP()); a != nil {
				ip = a.String()
			}
			if _, rest, ok := strings.Cut(lp.GetFqdn(), "."); ok {
				domain = rest
			}
			if ip != "" && domain != "" {
				break
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	if domain == "" {
		domain = "(none)"
	}
	if ip == "" {
		ip = "(pending)"
	}
	cmd.Printf("DNS domain: %s\n", domain)
	cmd.Printf("IP address: %s\n", ip)
}
