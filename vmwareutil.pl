#!perl
# Author: T.S. Davenport (todd.davenport@yahoo.com)
#
# Pulls performance metrics and/or metadata from vCenters
#
use VMware::VIRuntime;
use VMware::VILib;
use VMware::VIExt;
use strict;
$|++;

# Gather command line options
my $help         = 0;
my $listentities = 0;
my $counters     = 0;
my $entity       = 0;
my $entityType   = 0;
my $outputFile   = 0;
my $heirarchy    = 0;
my %opts = (
    help => {
        type => "",
        help => "Display help message\n",
        required => 0
    },
    listentities => {
        type => "=s",
        help => "List all entities of specified type\n",
        required => 0
    },
    countertypes => {
        type => "",
        help => "List all counter types on the specified vServer\n",
        required => 0
    },
    allstats => {
        type => "=s",
        help => "List all counter stats for the specified entity\n",
        required => 0
    },
    interval => {
        type => "=s",
        help => "Interval type to pull stats for (default 300)\n",
        required => 0
    },
    entitytype => {
        type => "=s",
        help => "Entity type. Required if --allstats used.\n",
        required => 0
    },
    outputfile => {
        type => "=s",
        help => "File name to write stats to. If not specified prints to STDOUT. Works with --allstats or --heirarchy.\n",
        required => 0
    },
    heirarchy => {
        type => "",
        help => "Get the heirarchy of entities.\n",
        required => 0
    }
);
Opts::add_options(%opts);
Opts::parse();
Opts::validate();
$help         = Opts::get_option("help");
$listentities = Opts::get_option("listentities");
$counters     = Opts::get_option("countertypes");
$entity       = Opts::get_option("allstats");
$entityType   = Opts::get_option("entitytype");
$outputFile   = Opts::get_option("outputfile");
$heirarchy    = Opts::get_option("heirarchy");

# Help task
if ($help) {
    &printHelp();

# List all entities
} elsif ($listentities) {
    &printEntityList($listentities);

# Print all counter types
} elsif ($counters) {
    &printAllCounters();

# Print all stats for entity
} elsif ($entity) {
    my $interval = 300;
    if (Opts::get_option("interval")) {
        $interval = Opts::get_option("interval");
    }
    if ($entityType) {
        &printStatsForEntity($entity,$entityType,$interval,$outputFile);
    } else {
        &printHelp();
    }

# Get heirarchy
} elsif ($heirarchy) {

    &printHeirarchy($outputFile);

# No input was understood
} else {
    &printHelp();
}

exit;

# Prints help message
sub printHelp {
    print<<EOF;
vmwareperfutil.pl

Gathers performance metrics for VMWare.

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

EOF
}

sub printHeirarchy { # ($outputFile)
    my($outputFile) = @_;
    
    # Prepare file if necessary
    my $fileH;
    if ($outputFile) {
        open $fileH, "+>", $outputFile or die "Can't open $outputFile:$!\n";
    } else {
        $fileH = \*STDOUT;
    }
    
    # login to vserver
    Util::connect();
    
    
    # Iterate the heirarchy
    #
    # Datacenter
    # ---Folder
    # ---ClusterComputeResource
    # ------ResourcePool
    # ------HostSystem
    # ---------VM
    my $datacenters = Vim::find_entity_views(
        view_type  => 'Datacenter',
        properties => [ 'name' ]
    );
    foreach my $datacenter (@$datacenters) {    
        print $fileH "DC: ", $datacenter->name . "\n";
        my $ccrs = Vim::find_entity_views(
            view_type    => 'ClusterComputeResource',
            begin_entity => $datacenter,
            properties   => [ 'name', 'host' ]
        );
        foreach my $ccr (@$ccrs) {
            print $fileH "---CCR: ", $ccr->name . "\n";
            my $hosts = Vim::get_views(
                mo_ref_array => $ccr->host,
                properties   => [ 'name', 'vm' ]
            );
            foreach my $host (@$hosts) {
                print $fileH "------HOST: ", $host->name . "\n";
                my $vms = Vim::get_views(
                    mo_ref_array => $host->vm,
                    properties   => [ 'name' ]
                );
                foreach my $vm (@$vms) {
                    print $fileH "---------VM: ", $vm->name . "\n";
                }
            }
            my $resources = Vim::find_entity_views(
                view_type    => 'ResourcePool',
                begin_entity => $ccr,
                properties   => [ 'name' ]
            );
            foreach my $resource (@$resources) {
                print $fileH "------RP: ", $resource->name . ",id=> ", $resource->get_property("mo_ref")->value . "\n";
            }
        }
        my $folders = Vim::find_entity_views(
            view_type    => 'Folder',
            begin_entity => $datacenter,
            properties   => [ 'name' ]
        );
        foreach my $folder (@$folders) {
            print $fileH "---FOLDER: ", $folder->name . "\n";
        }
    }
    
    # cleanup
    Util::disconnect();
    close $fileH;
}

# Prints a newline-separated list of all entities of <entityType>
sub printEntityList { # ($entityType)
    my($entityType) = @_;

    # Login
    Util::connect();

    # Get a list of all entities of this type
    my $entities = Vim::find_entity_views( view_type=>$entityType, properties=>['name'] );
    foreach my $entity (@$entities) {
        print $entity->name."\n";
    }

    Util::disconnect();
}

# Prints all counter types on this vServer
sub printAllCounters {

    # Login
    Util::connect();

    # Get perf manager
    my $perfManager = Vim::get_view(mo_ref => Vim::get_service_content()->perfManager);
    my $perfCounters = $perfManager->perfCounter;
    print "# ID,Name,Group,StatType,RollupType\n";
    foreach my $counter (@$perfCounters) {
        my $perfCounterID = $counter->key;
        my $group = $counter->groupInfo->key;
        my $name = $counter->nameInfo->key;
        my $statType = $counter->statsType->val;
        my $sumType  = $counter->rollupType->val;
        print "$perfCounterID,$group,$name,$statType,$sumType\n";
    }
    Util::disconnect();
}

# Prints all known stats for $entity
sub printStatsForEntity { # ($entity,$entityType,$interval,$outputFilename)
    my($entity,$type,$interval,$outputFile) = @_;

    unless ($outputFile) {
        print "ERROR: must specify an outputfile if getting all stats.\n";
        return;
    }

    Util::connect();

    # Handle to this vCenter's PerfManager
    my $perfManager = Vim::get_view(mo_ref => Vim::get_service_content()->perfManager);

    # Need to find the mo_ref for the entity
    my $entity_mo_ref = Vim::find_entity_view( view_type=>"$type", filter=>{'name'=>$entity}, properties=>['name'] );

    # Now get all stats
    # Examine the availability container and see which of the perfCounters are available for this entity
    my $availableMetrics;
    eval { $availableMetrics = $perfManager->QueryAvailablePerfMetric( entity=>$entity_mo_ref ); };
    if ($@) {
        print "WARNING: Unable to get counters for $entityType $entity\n";
        Util::disconnect();
        return;
    }

    # Construct a list of counters to pull for this particular entity
    my @countersToPull;

    #  Iterate the list of available metrics and create a counter query
    foreach my $availableMetricID (@$availableMetrics) {
        my $id   = $availableMetricID->counterId;
        my $inst = $availableMetricID->instance;
        my $pmi = PerfMetricId->new('counterId'=>$id, 'instance'=>$inst);
        push(@countersToPull, $pmi);
    }

    # Now construct the Query Spec, using the list of counters
    my $intervalID = 300;
    my $pqs = PerfQuerySpec->new( 'entity'=>$entity_mo_ref, 'format'=>'csv',
        'metricId'=>\@countersToPull, 'intervalId'=>$interval);

    # Make the query
    my $perfData = $perfManager->QueryPerf( 'querySpec'=>$pqs );

    # Prepare file if necessary
    my $fileH;
    if ($outputFile) {
        open $fileH, "+>", $outputFile or die "Can't open $outputFile:$!\n";
    } else {
        $fileH = \*STDOUT;
    }

    # Save out the data
    print $fileH "###entityType, entityName, counterID, instance, timestamps,...\n";

    # Iterate counters
    foreach my $p (@$perfData) {
        my @ts = split(/,/,$p->sampleInfoCSV);
        my @ts2;
        foreach (@ts) {
            next if (/^$interval$/);
            push(@ts2,$_);
        }

        # Print a header row
        print $fileH "\$\$\$$type,$entity,,,";
        print $fileH join(",",@ts2)."\n";
        my $pms = $p->value;
        foreach (@$pms) {
            my $id = $_->id;
            my $counterID = $id->counterId;
            my $instance  = $id->instance;
            print $fileH "$entityType,$entity,$counterID,";
            if ($instance) {
                print $fileH "$instance,";
            } else {
                print $fileH ",";
            }
            print $fileH $_->value."\n";
        }
    }
    Util::disconnect();
    close $fileH;
}

