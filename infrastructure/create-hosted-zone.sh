#!/bin/bash
# Creates a Route53 hosted zone for the domain and updates the domain's nameservers.
# Run this ONCE after terraform destroy wipes the hosted zone.
# setup.sh will automatically look up the zone ID from here.

set -e

DOMAIN="tulunad.click"
REGION="us-east-1"

# Check if hosted zone already exists
EXISTING=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$DOMAIN" --query "HostedZones[?Name=='${DOMAIN}.'].Id" --output text 2>/dev/null)

if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
  ZONE_ID=$(echo "$EXISTING" | cut -d'/' -f3)
  echo "Hosted zone already exists: $ZONE_ID"
else
  echo "Creating hosted zone for $DOMAIN..."
  RESULT=$(aws route53 create-hosted-zone \
    --name "$DOMAIN" \
    --caller-reference "$(date +%s)" \
    --output json)

  ZONE_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['HostedZone']['Id'].split('/')[-1])")
  echo "Created hosted zone: $ZONE_ID"
fi

# Get the NS records for the new zone
echo ""
echo "Fetching nameservers for zone $ZONE_ID..."
NS_RECORDS=$(aws route53 get-hosted-zone --id "$ZONE_ID" \
  --query "DelegationSet.NameServers" --output json)
echo "Nameservers: $NS_RECORDS"

# Check current domain nameservers
echo ""
echo "Checking domain's current nameservers..."
CURRENT_NS=$(aws route53domains get-domain-detail \
  --domain-name "$DOMAIN" --region "$REGION" \
  --query "Nameservers[].Name" --output json 2>/dev/null || echo "[]")
echo "Current: $CURRENT_NS"

# Compare and update if different
NS1=$(echo "$NS_RECORDS" | python3 -c "import sys,json; print(','.join(sorted(json.load(sys.stdin))))")
NS2=$(echo "$CURRENT_NS" | python3 -c "import sys,json; print(','.join(sorted(json.load(sys.stdin))))")

if [ "$NS1" = "$NS2" ]; then
  echo ""
  echo "Nameservers already match — no update needed."
else
  echo ""
  echo "Nameservers differ — updating domain registrar..."
  NS_ARGS=$(echo "$NS_RECORDS" | python3 -c "
import sys, json
ns = json.load(sys.stdin)
print(' '.join(f'Name={n}' for n in ns))
")
  aws route53domains update-domain-nameservers \
    --region "$REGION" \
    --domain-name "$DOMAIN" \
    --nameservers $NS_ARGS
  echo "Nameservers updated. DNS propagation may take a few minutes."
fi

echo ""
echo "Done. Hosted zone $ZONE_ID is ready."
echo "You can now run: ./setup.sh"
