#!/usr/bin/env bats

#
# Testing of common (aka passthrough) handler (this handler handles
# accesses to resources that are namespaced by the Linux kernel
# and for which no actual emulation is required).
#

load ../helpers/run
load ../helpers/fs
load ../helpers/ns

disable_ipv6=/proc/sys/net/ipv6/conf/all/disable_ipv6

function setup() {
  setup_busybox
}

function teardown() {
  teardown_busybox syscont
}

# compares /proc/* listings between a sys-container and unshare-all
# (there are expected to match, except for files emulated by sysvisor-fs)
function compare_syscont_unshare() {
  sc_list=$1
  ns_list=$2

  delta=$(diff --suppress-common-lines <(echo "$sc_list" | sed -e 's/ /\n/g') <(echo "$ns_list" | sed -e 's/ /\n/g') | grep "proc" | sed 's/^< //g')

  for file in $delta; do
    found=false
    for mnt in $SYSFS_PROC_SYS; do
      if [ "$file" == "$mnt" ]; then
        found=true
      fi
    done
    [ "$found" == true ]
  done
}

# lookup
@test "common handler: lookup" {

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # disable_ipv6
  sv_runc exec syscont sh -c "ls -l $disable_ipv6"
  [ "$status" -eq 0 ]

  verify_root_rw "$output"
  [ "$status" -eq 0 ]
}

@test "common handler: disable_ipv6" {

  local enable="0"
  local disable="1"

  host_orig_val=$(cat $disable_ipv6)

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # By default ipv6 should be enabled within a system container
  # launched by sysvisor-runc directly (e.g., without docker) Note
  # that in system container launched with docker + sysvisor-runc,
  # docker (somehow) disables ipv6.
  sv_runc exec syscont sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$enable" ]

  # Disable ipv6 in system container and verify
  sv_runc exec syscont sh -c "echo $disable > $disable_ipv6"
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$disable" ]

  # Verify that change in sys container did not affect host
  host_val=$(cat $disable_ipv6)
  [ "$host_val" -eq "$host_orig_val" ]

  # Re-enable ipv6 within system container
  sv_runc exec syscont sh -c "echo $enable > $disable_ipv6"
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "cat $disable_ipv6"
  [ "$status" -eq 0 ]
  [ "$output" = "$enable" ]

  # Verify that change in sys container did not affect host
  host_val=$(cat $disable_ipv6)
  [ "$host_val" -eq "$host_orig_val" ]
}

@test "common handler: /proc/sys hierarchy" {

  walk_proc="find /proc/sys -print"

  # launch sys container
  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  # get the list of dirs under /proc/sys
  sv_runc exec syscont sh -c "${walk_proc}"
  [ "$status" -eq 0 ]
  sc_proc_sys="$output"

  # unshare all ns and get the list of dirs under /proc/sys
  ns_proc_sys=$(unshare_all sh -c "${walk_proc}")

  compare_syscont_unshare "$sc_proc_sys" "$ns_proc_sys"
}

@test "common handler: /proc/sys perm" {

  # this lists all files and dirs under /proc/sys, each as:
  # -rw-r--r-- 1 root root /proc/sys/<path>
  l_proc_sys_files="find /proc/sys -type f -print0 | xargs -0 ls -l | awk '{print \$1 \" \" \$2 \" \" \$3 \" \" \$4 \" \" \$9}'"
  l_proc_sys_dirs="find /proc/sys -type d -print0 | xargs -0 ls -ld | awk '{print \$1 \" \" \$2 \" \" \$3 \" \" \$4 \" \" \$9}'"

  sv_runc run -d --console-socket $CONSOLE_SOCKET syscont
  [ "$status" -eq 0 ]

  sv_runc exec syscont sh -c "${l_proc_sys_files}"
  [ "$status" -eq 0 ]
  sc_proc_sys_files="$output"

  sv_runc exec syscont sh -c "${l_proc_sys_dirs}"
  [ "$status" -eq 0 ]
  sc_proc_sys_dirs="$output"

  ns_proc_sys_files=$(unshare_all sh -c "${l_proc_sys_files}")
  ns_proc_sys_dirs=$(unshare_all sh -c "${l_proc_sys_dirs}")

  compare_syscont_unshare "$sc_proc_sys_files" "$ns_proc_sys_files"
  compare_syscont_unshare "$sc_proc_sys_dirs" "$ns_proc_sys_dirs"
}
