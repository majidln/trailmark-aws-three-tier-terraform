# AWS Three-Tier Architecture with Terraform

![Abstract banner: three layered ridges under a connected night sky, with a glowing trail winding up toward the sunrise](docs/banner.svg)

N-tier architecture is a classic way to design software systems. The application is split into separate tiers, typically presentation, application logic and data, and each tier has its own network boundary that controls what can reach it (ingress) and what it can reach (egress). This project walks step by step through implementing a three-tier application on AWS.

We use Terraform, an infrastructure-as-code (IaC) tool, to build the whole solution, so every resource below is declared in code, reviewed in pull requests and reproducible.

## 1. The VPC

Everything starts with the VPC, the private network that all three tiers live in (`modules/network/main.tf`):

```hcl
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.prefix}-vpc"
    Environment = var.environment
  }
}
```

### The CIDR block

The VPC gets `10.0.0.0/16` (the default of the `vpc_cidr` variable): a private range of 65,536 addresses, `10.0.0.0` to `10.0.255.255`. The `/16` is the largest block AWS allows for a VPC, which leaves plenty of room to carve out subnets for all three tiers.

I split it into six `/24` subnets, two per tier, one in each of two Availability Zones. Terraform computes them with `cidrsubnet(var.vpc_cidr, 8, n)`, so the subnet ranges follow whatever range the VPC is given:

| Tier | AZ 1 | AZ 2 |
|---|---|---|
| public (ALB) | `10.0.0.0/24` | `10.0.1.0/24` |
| private (app) | `10.0.10.0/24` | `10.0.11.0/24` |
| isolated (db) | `10.0.20.0/24` | `10.0.21.0/24` |

Each tier starts at its own offset (0, 10 and 20), so the third octet shows which tier an address belongs to.

DNS support and DNS hostnames are both enabled so that resources in the VPC, such as the RDS endpoint, resolve by name.

## 2. The subnets

A subnet is a slice of the VPC's address range that lives in exactly one Availability Zone. A subnet cannot span AZs, but an AZ can hold many subnets. That is why each tier gets one subnet per AZ: losing an AZ takes out only half of each tier.

```hcl
resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az
  tags = {
    Name        = "${var.prefix}-${each.key}"
    Tier        = each.value.tier
    Environment = var.environment
  }
}
```

One resource block creates all six subnets. `local.subnets` is a map with one entry per subnet (`public-1`, `public-2`, `app-1`, and so on), holding its CIDR block, its AZ and its tier. `for_each` turns each entry into a subnet. The number of AZs is the `az_count` variable (default 2, minimum 2): the module takes the first `az_count` AZ names in the region, in sorted order, and creates one subnet per tier in each. Changing `az_count` changes the number of subnets, and everything built on them (ALB, Auto Scaling Group, route tables, and in prod the NAT gateways) follows it, without touching this block. The `Tier` tag records which tier a subnet belongs to.

## 3. Internet access for the public subnets

A subnet is not public by itself. It is public when its route table sends internet-bound traffic to an internet gateway. So the next step is an internet gateway for the VPC, a route table with a default route to it, and an association of that route table with the public subnets:

```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.prefix}-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "web-route-table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.prefix}-web-route-table"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "web-route-table-association" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.web-route-table.id
}
```

- The internet gateway belongs to the VPC, not to an AZ, and AWS runs it redundantly, so one gateway serves every public subnet.
- `0.0.0.0/0` is the default route: anything that doesn't match a more specific route, such as the VPC's own range, goes to the internet gateway.
- The association is what makes the subnets public. Only the two public subnets get this route table, so the app and db subnets have no path to the internet gateway.
- The route is necessary but not sufficient. The ALB, the only resource in the public subnets, is internet-facing and gets public addresses from AWS, and its security group allows port 80 from `0.0.0.0/0`.

## 4. NAT gateways for the private subnets

The app instances sit in private subnets with no route to the internet gateway, but they still need outbound access for package installs and updates. A NAT gateway provides it: it sits in a public subnet, has an Elastic IP, and lets instances in the private subnets start connections to the internet while nothing on the internet can start a connection to them.

```hcl
resource "aws_eip" "nat" {
  for_each = local.nat_subnets

  domain = "vpc"

  tags = {
    Name        = "${var.prefix}-eip-${each.key}"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_subnets

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[each.key].id

  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name        = "${var.prefix}-nat-${each.key}"
    Environment = var.environment
  }
}
```

### Cost against availability

A NAT gateway is one of the most expensive parts of this stack: it is billed for every hour it exists, plus for every GB that passes through it. It is also a zonal resource, so if its AZ goes down, every subnet routed through it loses outbound access. The `single_nat_gateway` variable lets each environment choose the trade-off:

| | `single_nat_gateway` | NAT gateways | Trade-off |
|---|---|---|---|
| dev | `true` | one, shared by all app subnets | cheapest; outbound access is lost if that AZ fails |
| prod | `false` | one per AZ | costs more; each AZ keeps its own outbound path, so an AZ failure doesn't affect the others |

The variable works through `local.nat_subnets`: with `true` it holds only the first public subnet, so one NAT gateway and one Elastic IP are created. With `false` it holds every public subnet.

## 5. Routing the app subnets through the NAT

A NAT gateway does nothing until a route points at it. Each app subnet gets its own route table, with a default route to the NAT gateway in the same AZ, and an association to attach it to the subnet:

```hcl
resource "aws_route_table" "app-route-table" {
  for_each = local.app_subnets

  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = lookup(local.nat_gateway_by_az, each.value.az, local.fallback_nat_gateway_id)
  }

  tags = {
    Name        = "${var.prefix}-app-route-table-${each.key}"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "app-route-table-association" {
  for_each = local.app_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.app-route-table[each.key].id
}
```

The `lookup` picks the NAT gateway in the subnet's own AZ, so traffic doesn't cross AZs when prod has one per AZ. If the AZ has no NAT gateway, as in dev, it falls back to the first one. This is why the app tier needs a route table per subnet, while the public tier shares one.

The db subnets get no route to a NAT gateway or an internet gateway, so the database has no path to the internet in either direction.
