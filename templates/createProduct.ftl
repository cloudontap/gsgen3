[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = credentials?eval]
[#assign configurationObject = configuration?eval]
[#assign stackOutputsObject = stackOutputs?eval]

[#-- High level objects --]
[#assign tenantObject = blueprintObject.Tenant]
[#assign accountObject = blueprintObject.Account]
[#assign productObject = blueprintObject.Product]
[#assign solutionObject = blueprintObject.Solution]
[#assign solutionTiers = solutionObject.Tiers]
[#assign segmentObject = blueprintObject.Segment]

[#-- Reference data --]
[#assign regions = blueprintObject.Regions]
[#assign environments = blueprintObject.Environments]
[#assign categories = blueprintObject.Categories]
[#assign tiers = blueprintObject.Tiers]
[#assign routeTables = blueprintObject.RouteTables]
[#assign networkACLs = blueprintObject.NetworkACLs]
[#assign storage = blueprintObject.Storage]
[#assign processors = blueprintObject.Processors]
[#assign ports = blueprintObject.Ports]
[#assign portMappings = blueprintObject.PortMappings]

[#-- Reference Objects --]
[#assign regionObject = regions[region]]
[#assign productRegionObject = regions[productRegion]]
[#assign accountRegionObject = regions[accountRegion]]
[#assign environmentObject = environments[segmentObject.Environment]]
[#assign categoryObject = categories[segmentObject.Category!environmentObject.Category]]

[#-- Key ids/names --]
[#assign tenantId = tenantObject.Id]
[#assign accountId = accountObject.Id]
[#assign productId = productObject.Id]
[#assign productName = productObject.Name]
[#assign segmentId = segmentObject.Id!environmentObject.Id]
[#assign segmentName = segmentObject.Name!environmentObject.Name]
[#assign regionId = regionObject.Id]
[#assign productRegionId = productRegionObject.Id]
[#assign accountRegionId = accountRegionObject.Id]
[#assign environmentId = environmentObject.Id]
[#assign environmentName = environmentObject.Name]
[#assign categoryId = categoryObject.Id]

[#-- Domains --]
[#assign productDomainStem = (productObject.Domain.Stem)!"gosource.com.au"]
[#assign productDomainBehaviour = (productObject.Domain.ProductBehaviour)!""]
[#switch productDomainBehaviour]
    [#case "naked"]
        [#assign productDomain = productDomainStem]
        [#break]
    [#case "includeProductId"]
    [#default]
        [#assign productDomain = productId + "." + productDomainStem]
[/#switch]

[#-- Get stack output --]
[#function getKey key]
    [#list stackOutputsObject as pair]
        [#if pair.OutputKey==key]
            [#return pair.OutputValue]
        [/#if]
    [/#list]
[/#function]

[#-- Product --]
[#assign snsEnabled = false]

{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : { 
        [#assign count = 0]
        [#-- SNS for product --]
        [#if snsEnabled]
            "snsXalerts" : {
                "Type": "AWS::SNS::Topic",
                "Properties" : {
                    "DisplayName" : "${(productName + "-alerts")[0..9]}",
                    "TopicName" : "${productName}-alerts",
                    "Subscription" : [
                        {
                            "Endpoint" : "alerts@${productDomain}", 
                            "Protocol" : "email"
                        }
                    ]
                }
            } 
            [#assign count = count + 1]
        [/#if]
        [#-- Shared product level resources if we are in the product region --]
        [#if (regionId == productRegionId)]
            [#if solutionObject.SharedComponents??]
                [#list solutionObject.SharedComponents as component] 
                    [#if component.S3??]
                        [#assign s3 = component.S3]
                        [#if count > 0],[/#if]
                        "s3X${component.Id}" : {
                            "Type" : "AWS::S3::Bucket",
                            "Properties" : {
                                [#if s3.Name??]
                                    "BucketName" : "${s3.Name}.${productDomain}",
                                [#else]
                                    "BucketName" : "${component.Name}.${productDomain}",
                                [/#if]
                                "Tags" : [ 
                                    { "Key" : "gs:product", "Value" : "${productId}" },
                                    { "Key" : "gs:category", "Value" : "${categoryId}" }
                                ]
                                [#if s3.Lifecycle??]
                                    ,"LifecycleConfiguration" : {
                                        "Rules" : [
                                            {
                                                "Id" : "default",
                                                [#if s3.Lifecycle.Expiration??]
                                                    "ExpirationInDays" : ${s3.Lifecycle.Expiration},
                                                [/#if]
                                                "Status" : "Enabled"
                                            }
                                        ]
                                    }
                                [/#if]
                            }
                        }
                        [#assign count = count + 1]
                    [/#if]
                [/#list]
            [/#if]
        [/#if]
    },
    
    "Outputs" : {
        [#assign count = 0]
        [#if snsEnabled]
            "snsXproductXalertsX${regionId?replace("-","")}" : {
                "Value" : { "Ref" : "snsXalerts" }
            }
            [#assign count = count + 1]
        [/#if]
        [#if (regionId == productRegionId)]
            [#if count > 0],[/#if]
            "domainXproductXdomain" : {
                "Value" : "${productDomain}"
            }
            [#if solutionObject.SharedComponents??]
                [#list solutionObject.SharedComponents as component] 
                    [#if component.S3??]
                        ,"s3XproductX${component.Id}" : {
                            "Value" : { "Ref" : "s3X${component.Id}" }
                        }
                    [/#if]
                [/#list]
            [/#if]
        [/#if]
    }
}
