[#ftl]
{
    "Solution" : {
        "Title" : "Docker based alpha stage project system",
        "Id" : "alpha-docker",
        "Name" : "alpha-docker",
        [#if region??]
            "Region" : "${region}",
        [/#if]
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
                            "Ports" : ["http", "ssh"],
                            "Processor" : {
                            "Processor" : "t2.small",
                            "MinPerZone" : 1,
                            "MaxPerZone" : 1,
                            "DesiredPerZone" : 1,
                            "Cpu" : 1024,
                            "Memory" : 2048
                            },
                            "Storage" : {
                            "Volumes" : [
                            {
                            "Device" : "/dev/sdp",
                            "Size" : "20"
                            }
                            ]
                            }
                            }
                            }
                ]
            }
        ]
    },
    "Segment" : {
        "BClass" : "10.0",
        "InternetAccess" : true,
        "DNSSupport" : true,
        "DNSHostnames" : true,
        "SSHPerSegment" : false
    }
}
