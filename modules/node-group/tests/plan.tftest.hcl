# Copyright 2026 BitWise Media Group Ltd
# SPDX-License-Identifier: MIT

# Plan-time contract tests with a mocked provider: the launch-template wiring
# (cluster security group always attached, root device per OS family, IMDSv2)
# and the node-group shape (scaling, labels, taints, auto-repair).

mock_provider "aws" {}

variables {
  cluster_name              = "patchy-x"
  name                      = "workers"
  node_role_arn             = "arn:aws:iam::123456789012:role/patchy-x-nodes"
  subnet_ids                = ["subnet-0aaa", "subnet-0bbb"]
  cluster_security_group_id = "sg-0cluster"
}

run "launch_template_wiring" {
  command = plan

  variables {
    security_group_ids = ["sg-0extra"]
  }

  assert {
    condition     = aws_launch_template.main.vpc_security_group_ids == toset(["sg-0cluster", "sg-0extra"])
    error_message = "extra security groups must attach alongside the cluster security group, never instead of it"
  }

  assert {
    condition     = aws_launch_template.main.block_device_mappings[0].device_name == "/dev/xvda"
    error_message = "Linux AMI families root on /dev/xvda; the disk size must land on that device"
  }

  assert {
    condition     = aws_launch_template.main.block_device_mappings[0].ebs[0].volume_size == 50 && aws_launch_template.main.block_device_mappings[0].ebs[0].volume_type == "gp3"
    error_message = "the root volume must be gp3 at the configured size"
  }

  assert {
    condition     = aws_launch_template.main.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be enforced on every node"
  }

  assert {
    condition     = aws_eks_node_group.main.node_group_name_prefix == "workers-"
    error_message = "the node group name must be a prefix so a replacement never collides with the group it supersedes"
  }
}

run "windows_node_group" {
  command = plan

  variables {
    ami_type = "WINDOWS_CORE_2022_x86_64"
  }

  assert {
    condition     = aws_eks_node_group.main.ami_type == "WINDOWS_CORE_2022_x86_64"
    error_message = "the ami_type must pass through to the node group"
  }

  assert {
    condition     = aws_launch_template.main.block_device_mappings[0].device_name == "/dev/sda1"
    error_message = "Windows AMIs root on /dev/sda1; sizing /dev/xvda would add a second, unused volume"
  }
}

run "node_group_shape" {
  command = plan

  variables {
    min_size     = 1
    max_size     = 6
    desired_size = 3
    labels       = { role = "workers" }
    taints = [
      { key = "node.cilium.io/agent-not-ready", value = "true", effect = "NO_EXECUTE" },
    ]
  }

  assert {
    condition     = aws_eks_node_group.main.scaling_config[0].min_size == 1 && aws_eks_node_group.main.scaling_config[0].max_size == 6 && aws_eks_node_group.main.scaling_config[0].desired_size == 3
    error_message = "the scaling config must carry the configured cluster-wide totals"
  }

  assert {
    condition     = aws_eks_node_group.main.labels["role"] == "workers"
    error_message = "labels must pass through to the nodes"
  }

  assert {
    condition = one([
      for taint in aws_eks_node_group.main.taint :
      taint if taint.key == "node.cilium.io/agent-not-ready" && taint.effect == "NO_EXECUTE"
    ]) != null
    error_message = "taints must pass through to the nodes"
  }

  assert {
    condition     = aws_eks_node_group.main.node_repair_config[0].enabled == true
    error_message = "node auto-repair must be on"
  }

  assert {
    condition     = aws_eks_node_group.main.update_config[0].max_unavailable == 1
    error_message = "rolling updates must take nodes one at a time"
  }
}

run "bottlerocket_is_rejected" {
  command = plan

  variables {
    ami_type = "BOTTLEROCKET_x86_64"
  }

  expect_failures = [var.ami_type]
}

run "invalid_taint_effect_is_rejected" {
  command = plan

  variables {
    taints = [
      { key = "dedicated", value = "gpu", effect = "NoSchedule" },
    ]
  }

  expect_failures = [var.taints]
}
