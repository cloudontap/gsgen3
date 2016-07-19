[#ftl]
{
    "Organisation" : {
        "Title" : "${organisation}",
        "Id" : "${id}",
        "Name" : "${name}"
        [#if Description??],
            "Description" : "${description}"
        [/#if]
    }
}
