#!/usr/bin/expect
#

set timeout 40

spawn telnet localhost 4000

expect {
    eof {puts "Connection problem, exiting."; exit 1}
    timeout {puts "System did not boot in time, exiting."; exit 1}
    "buildroot login:"
}
send "root\r"
expect {
    eof {puts "Connection problem, exiting."; exit 1}
    timeout {puts "No shell, exiting."; exit 1}
    "# "
}
send "poweroff\r"
expect "System halted"



