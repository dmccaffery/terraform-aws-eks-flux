# Copyright 2026 BitWise Media Group Ltd
# SPDX-License-Identifier: MIT

# The delegated Route53 hosted zone (e.g. patchy.bitwisemedia.co.uk) is created
# upstream and delegated from the parent domain once — it deliberately lives
# outside this module so cluster destroy/recreate never touches the zone or its
# NS delegation. This module only looks it up: validating it exists, deriving
# the domain for the Gateway/certificate wiring, and passing the id through to
# external-dns via cluster vars. The zone can exist in a public and/or a
# private flavour under the same name (var.dns.public_zone / private_zone):
# a private zone associated with the cluster VPC shadows the public one for
# in-VPC resolution, so split-horizon deployments enable both and external-dns
# publishes the same records into each.

locals {
  # The zone flavours the caller enabled — public first, so it drives the
  # primary id/domain when both exist. Validation guarantees at least one
  # whenever zone_name is set.
  dns_zone_kinds = var.dns.zone_name == null ? [] : concat(
    var.dns.public_zone ? ["public"] : [],
    var.dns.private_zone ? ["private"] : [],
  )
}

data "aws_route53_zone" "cluster" {
  for_each = toset(local.dns_zone_kinds)

  name         = "${trimsuffix(var.dns.zone_name, ".")}."
  private_zone = each.key == "private"
}

locals {
  # Zone apex without the trailing dot (patchy.bitwisemedia.co.uk.).
  dns_domain  = var.dns.zone_name != null ? trimsuffix(data.aws_route53_zone.cluster[local.dns_zone_kinds[0]].name, ".") : null
  dns_zone_id = var.dns.zone_name != null ? data.aws_route53_zone.cluster[local.dns_zone_kinds[0]].zone_id : null

  # The public host the patchy webhook is served on: the zone apex unless the
  # caller narrows it to a sub-host.
  patchy_domain = var.dns.zone_name != null ? coalesce(var.dns.host, local.dns_domain) : null
}
