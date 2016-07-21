[#ftl]
{
    "Account" : {
        "Title" : "${account}",
        "Id" : "${id}",
        "Name" : "${name}",
        [#if description??]
            "Description" : "${description}",
        [/#if]
        "Region" : "${region}",
        "SESRegion" : "${sesRegion}"
    },
    "Segment" : {
        "BClass" : "10.0",
        "InternetAccess" : true,
        "DNSSupport" : true,
        "DNSHostnames" : true,
        "NAT" : {
            "Enabled" : true,
            "MultiAZ" : false
        },
        "SSHPerSegment" : false,
        "RotateKey" : true
    }
}
