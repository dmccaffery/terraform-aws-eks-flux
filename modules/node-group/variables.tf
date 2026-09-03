# Copyright 2026 BitWise Media Group Ltd
# SPDX-License-Identifier: MIT

variable "cluster_name" {
  description = "Name of the EKS cluster the node group joins."
  type        = string
  nullable    = false
}

variable "name" {
  description = <<-EOT
    Node group name stem. Used as a name prefix, so a replacement never collides with the group it supersedes.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,36})$", var.name))
    error_message = "name must be a short lowercase RFC-1035 label (it prefixes the node group and launch template names)."
  }
}

variable "node_role_arn" {
  description = <<-EOT
    IAM role the nodes run as. Its access entry type (EC2_LINUX / EC2_WINDOWS) must match ami_type's OS family.
  EOT
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "Subnets the nodes launch into."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must name at least one subnet."
  }
}

variable "cluster_security_group_id" {
  description = <<-EOT
    The EKS-managed cluster security group. Always attached - without it nodes cannot reach the control plane.
  EOT
  type        = string
  nullable    = false
}

variable "security_group_ids" {
  description = "Additional security groups the launch template attaches alongside the cluster security group."
  type        = set(string)
  nullable    = false
  default     = []
}

variable "instance_types" {
  description = "Instance types the node group launches, in preference order."
  type        = list(string)
  nullable    = false
  default     = ["m7i.large"]
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT capacity."
  type        = string
  nullable    = false
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "min_size" {
  description = "Minimum node count (cluster-wide total, not per-zone)."
  type        = number
  nullable    = false
  default     = 2
}

variable "max_size" {
  description = "Maximum node count (cluster-wide total, not per-zone)."
  type        = number
  nullable    = false
  default     = 4
}

variable "desired_size" {
  description = <<-EOT
    Initial node count. Set once at create and never argued about again (ignore_changes) - the count is Kubernetes' to
    move on a live cluster.
  EOT
  type        = number
  nullable    = false
  default     = 2
}

variable "disk_size_gib" {
  description = "Root volume size in GiB (gp3), set through the launch template."
  type        = number
  nullable    = false
  default     = 50
}

variable "ami_type" {
  description = <<-EOT
    EKS AMI type. Null takes the EKS default for the instance architecture (AL2023). WINDOWS_* types launch Windows
    nodes - pair them with a node role admitted through an EC2_WINDOWS access entry. Bottlerocket is deliberately
    unsupported: its two-volume layout (a separate data volume) does not fit the single root device this module's
    launch template sizes.
  EOT
  type        = string
  nullable    = true
  default     = null

  validation {
    condition     = var.ami_type == null || can(regex("^(AL2023_|WINDOWS_)", var.ami_type))
    error_message = "ami_type must be an AL2023_* or WINDOWS_* EKS AMI type (or null for the EKS default)."
  }
}

variable "labels" {
  description = "Kubernetes labels applied to every node in the group."
  type        = map(string)
  nullable    = false
  default     = {}
}

variable "taints" {
  description = "Kubernetes taints applied to every node in the group."
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  nullable = false
  default  = []

  validation {
    condition = alltrue([
      for taint in var.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], taint.effect)
    ])
    error_message = "Each taint effect must be NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE."
  }
}

variable "tags" {
  description = <<-EOT
    Tags applied to every resource this module creates (and, via the launch template, to the instances and volumes).
  EOT
  type        = map(string)
  nullable    = false
  default     = {}
}
