[#ftl]
{
    "Solution" : {
        "Title" : "Basic network to enable launching of alpha stage project systems",
        "Id" : "alpha",
        "Name" : "alpha",
        "Tiers" : [
            {
                "Id" : "web",
                "RouteTable" : "external"
            }
        ]
    },
    "Segment" : {
        "SSHPerSegment" : true,
        "NAT" : {
            "Enabled" : false
        }
    }
}
