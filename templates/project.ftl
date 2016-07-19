[#ftl]
{
    "Project" : {
        "Title" : "${project}",
        "Id" : "${id}",
        "Name" : "${name}"
        [#if description??],
            "Description" : "${description}"
        [/#if]
    }
}
