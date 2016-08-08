[#ftl]
{
    "Product" : {
        "Title" : "${product}",
        "Id" : "${id}",
        "Name" : "${name}"
        [#if description??],
            "Description" : "${description}"
        [/#if]
    }
}
