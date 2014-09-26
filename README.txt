vmwareutils.pl
Version 1.0
by T.S. Davenport (todd.davenport@yahoo.com)

1. PURPOSE

Tools for working with VMWare server

2. REQUIREMENTS / PRE-REQUISITES

-Requires VMware Perl SDK (https://developercenter.vmware.com/web/sdk/55/vsphere-perl)
-Only ever tested on Windows

3. USAGE

Required:
--username Username for vCenter server
--password Password for vCenter server
--server   IP or hostname of vCenter server

Optional:
--listentities <entityType> Provide a list of all entities of <entityType>
                            Type must be one of: Datacenter HostSystem ClusterComputeResource
                            VirtualMachine ResourcePool Folder
--countertypes              List all available counter types on this vServer
--allstats <entity>         List all counter stats for the specified entity
--entitytype <entityType>   If using --allstats, must specify the entity type with this option.
--interval <num>            Interval value to use in data pull. Defaults to 300 (seconds)
--heirarchy                 Get the heirarchy of entities
--outputfile <filename>     File name to write stats to. If not specified prints to STDOUT.
                            Works with --allstats or --heirarchy
--help                      Print this usage message
