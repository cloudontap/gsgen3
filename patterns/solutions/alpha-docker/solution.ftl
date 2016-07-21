[#ftl]
{
    "Solution" : {
        "Title" : "Docker based alpha stage project system",
        "Id" : "alpha-docker",
        "Name" : "alpha-docker",
        "Tiers" : [
            {
                "Id" : "elb",
                "Components" : [
                    {
                        "Title" : "Website Load Balancer",
                        "Id" : "www",
                        "Name" : "www",
                        "Slices" : ["website"],
                        "ELB" : {
                            "PortMappings" : ["https"]
                        }
                    }
                ]
            },
            {
                "Id" : "web",
                "RouteTable" : "external",
                "Components" : [
                    {
                        "Title" : "Web Server",
                        "Id" : "www",
                        "Name" : "www",
                        "Slices" : ["website"],
                        "Role" : "ECS",
                        "ECS" : {
                            "Ports" : ["http", "ssh"]
                        }
                    }
                ]
            }
        ]
    },
    "Segment" : {
        "SSHPerSegment" : true,
        "NAT" : {
            "Enabled" : false
        }
    },
    "Processors" : {
        "default" : {
            "ECS" : {
                "Processor" : "t2.small",
            }
        }
    },
    "Storage" : {
        "default" : {
            "ECS" : {
                "Volumes" : [
                    {
                        "Device" : "/dev/sdp",
                        "Size" : "20"
                    }
                ]
            }
        }
    }
}
