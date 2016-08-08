[#ftl]
{
    "Tenant" : {
        "Title" : "${tenant}",
        "Id" : "${id}",
        "Name" : "${name}"
        [#if Description??],
            "Description" : "${description}"
        [/#if]
    }
}
