#!/usr/bin/expect
#

set timeout 40

spawn telnet localhost 4000

expect "buildroot login:"
send "root\r"
expect "# "
send "poweroff\r"
expect "System halted"



