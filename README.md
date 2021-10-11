# ATXRaspi-SoftBTN-Shutdown
Script triggers ATXRaspi SoftBTN.

Save softbtn.sh in /sbin directory and make executable. 
Save softbtn.service in /etc/systemd/system. 
Refresh systemd configuration files systemctl daemon-reload. 
Enable script systemctl enable softbtn
