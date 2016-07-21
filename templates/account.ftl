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
    }
}
