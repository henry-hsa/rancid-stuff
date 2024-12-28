# rancid-stuff

1. ios.pm 
   
   patched to get rid of timestamp_write , as some of the ZTE OLT C320 producing this while taking some configurations.
   using ios.pm instead of a dedicated module as a temporary solution. All other Cisco devices appear to work well with this configuration
2. control_rancid 
   
   patched give more human readable in diff git results while  notified via email.