package cmd

import (
	"context"
	"net"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/netbirdio/netbird/client/proto"
)

// printConnectionSummary prints, after "Connected", this machine's full DNS name
// as assigned by the management server (e.g. sidj.zt.slb) and its assigned IP address.
// The daemon may need a moment to publish them, so poll briefly.
func printConnectionSummary(ctx context.Context, cmd *cobra.Command, client proto.DaemonServiceClient) {
	var ip, fqdn string
	for i := 0; i < 20; i++ {
		resp, err := client.Status(ctx, &proto.StatusRequest{GetFullPeerStatus: true})
		if err == nil {
			lp := resp.GetFullStatus().GetLocalPeerState()
			if addr, _, perr := net.ParseCIDR(lp.GetIP()); perr == nil {
				ip = addr.String()
			} else if a := net.ParseIP(lp.GetIP()); a != nil {
				ip = a.String()
			}
			fqdn = strings.TrimSuffix(lp.GetFqdn(), ".")
			if ip != "" && fqdn != "" {
				break
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	if fqdn == "" {
		fqdn = "(none)"
	}
	if ip == "" {
		ip = "(pending)"
	}
	cmd.Printf("DNS domain: %s\n", fqdn)
	cmd.Printf("IP address: %s\n", ip)
}
