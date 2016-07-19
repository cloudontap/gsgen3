[#ftl]
{
    "Solution" : {
        "Title" : "Basic network to enable launching of alpha stage project systems",
        "Id" : "alpha",
        "Name" : "alpha",
        [#if region??]
            "Region" : "${region}",
        [/#if]
        "Tiers" : [
            {
                "Id" : "web",
                "RouteTable" : "external"
            }
        ]
    },
    "Segment" : {
        "BClass" : "10.0",
        "InternetAccess" : true,
        "DNSSupport" : true,
        "DNSHostnames" : true,
        "SSHPerSegment" : true
    }
}
