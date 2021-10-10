# ATXRaspi-SoftBTN-Shutdown
Replacement shutdown script to trigger shutdown via ATXRaspi's SoftBTN

Rename existing shutdown script in /sbin to shutdownoriginal
Add new shutdown script to /sbin, make executable
Update "Button" in shutdown script to reflect correct GPIO pin number


Calling "shutdown" or "shutdown now" will trigger ATXRaspi SoftBTN and prompt shutdown. Any other arguments are passed to the original shutdown script. Scheduled shutdowns will not trigger SoftBTN. 
