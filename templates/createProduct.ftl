[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = credentials?eval]
[#assign appSettingsObject = appsettings?eval]
[#assign stackOutputsObject = stackOutputs?eval]

[#-- High level objects --]
[#assign tenantObject = blueprintObject.Tenant]
[#assign accountObject = blueprintObject.Account]
[#assign productObject = blueprintObject.Product]
[#assign sharedComponentsPresent = (blueprintObject.Solution.SharedComponents)?? ]
[#if sharedComponentsPresent]
    [#assign sharedComponents = blueprintObject.Solution.sharedComponents]
[/#if]
    
[#-- Reference data --]
[#assign regions = blueprintObject.Regions]

[#-- Reference Objects --]
[#assign regionObject = regions[region]]
[#assign accountRegionObject = regions[accountRegion]]
[#assign productRegionObject = regions[productRegion]]

[#-- Key ids/names --]
[#assign tenantId = tenantObject.Id]
[#assign accountId = accountObject.Id]
[#assign productId = productObject.Id]
[#assign productName = productObject.Name]
[#assign regionId = regionObject.Id]
[#assign accountRegionId = accountRegionObject.Id]
[#assign productRegionId = productRegionObject.Id]

[#-- Domains --]
[#assign productDomainStem = productObject.Domain.Stem]
[#assign productDomainBehaviour = (productObject.Domain.ProductBehaviour)!""]
[#assign productDomainCertificateId = productObject.Domain.Certificate.Id]
[#switch productDomainBehaviour]
    [#case "productInDomain"]
        [#assign productDomain = productName + "." + productDomainStem]
        [#assign productDomainQualifier = ""]
        [#assign productDomainCertificateId = productDomainCertificateId + "-" + productId]
        [#break]
    [#case "naked"]
        [#assign productDomain = productDomainStem]
        [#assign productDomainQualifier = ""]
        [#break]
    [#case productInHost]    
    [#default]
        [#assign productDomain = productDomainStem]
        [#assign productDomainQualifier = "-" + productName]
        [#break]
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
[#assign rotateKeys = (productObject.RotateKeys)!true]

{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : { 
        [#assign sliceCount = 0]
        [#if slice?contains("cmk")]
            [#-- Key for product --]
            [#if sliceCount > 0],[/#if]
            "cmk" : {
                "Type" : "AWS::KMS::Key",
                "Properties" : {
                    "Description" : "${productName}",
                    "Enabled" : true,
                    "EnableKeyRotation" : ${(rotateKeys)?string("true","false")},
                    "KeyPolicy" : {
                        "Version": "2012-10-17",
                        "Statement": [ 
                            {
                                "Effect": "Allow",
                                "Principal": { 
                                    "AWS": { 
                                        "Fn::Join": [
                                            "", 
                                            [
                                                "arn:aws:iam::",
                                                { "Ref" : "AWS::AccountId" },
                                                ":root"
                                            ]
                                        ]
                                    }
                                },
                                "Action": [ "kms:*" ],
                                "Resource": "*"
                            }
                        ]
                    }
                }
            }
            [#assign sliceCount = sliceCount + 1]
        [/#if]
        
        [#if slice?contains("cert")]
            [#-- Generate certificate --]
            [#if sliceCount > 0],[/#if]
            "certificate" : {
                "Type" : "AWS::CertificateManager::Certificate",
                "Properties" : {
                    "DomainName" : "*.${productDomain}",
                    "DomainValidationOptions" : [
                        {
                            "DomainName" : "*.${productDomain}",
                            "ValidationDomain" : "${tenantObject.Domain.Validation}"
                        }
                    ]
                }
            }
            [#assign sliceCount = sliceCount + 1]
        [/#if]

        [#if slice?contains("sns")]
            [#-- SNS for product --]
            [#if sliceCount > 0],[/#if]
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
            [#assign sliceCount = sliceCount + 1]
        [/#if]
       
        [#if slice?contains("shared")]
            [#if (regionId == productRegionId)]
                [#if sharedComponentsPresent]
                    [#if sliceCount > 0],[/#if]
                    [#assign sharedCount = 0]
                    [#list sharedComponents as component] 
                        [#if component.S3??]
                            [#assign s3 = component.S3]
                            [#if sharedCount > 0],[/#if]
                            "s3X${component.Id}" : {
                                "Type" : "AWS::S3::Bucket",
                                "Properties" : {
                                    [#if s3.Name??]
                                        "BucketName" : "${s3.Name}${productDomainQualifier}.${productDomain}",
                                    [#else]
                                        "BucketName" : "${component.Name}${productDomainQualifier}.${productDomain}",
                                    [/#if]
                                    "Tags" : [ 
                                        { "Key" : "cot:request", "Value" : "${request}" },
                                        { "Key" : "cot:product", "Value" : "${productId}" },
                                        { "Key" : "cot:category", "Value" : "${categoryId}" }
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
                            [#assign sharedCount = sharedCount + 1]
                        [/#if]
                    [/#list]
                    [#assign sliceCount = sliceCount + 1]
                [/#if]
            [/#if]
        [/#if]
    },
    
    "Outputs" : {
        [#assign sliceCount = 0]
        [#if slice?contains("cmk")]
            [#if sliceCount > 0],[/#if]
            "cmkXproductXcmk" : {
                "Value" : { "Ref" : "cmk" }
            }
            [#assign sliceCount = sliceCount + 1]
        [/#if]

        [#if slice?contains("cert")]
            [#if sliceCount > 0],[/#if]
            "certificateX${productDomainCertificateId}" : {
                "Value" : { "Ref" : "certificate" }
            }
            [#assign sliceCount = sliceCount + 1]
        [/#if]

        [#if slice?contains("sns")]
            [#if sliceCount > 0],[/#if]
            "snsXproductXalertsX${regionId?replace("-","")}" : {
                "Value" : { "Ref" : "snsXalerts" }
            }
        [/#if]
        
        [#if slice?contains("shared")]
            [#if (regionId == productRegionId)]
                [#if sliceCount > 0],[/#if]
                "domainXproductXdomain" : {
                    "Value" : "${productDomain}"
                }
                ,"domainXproductXqualifier" : {
                    "Value" : "${productDomainQualifier}"
                }
                [#if sharedComponentsPresent]
                    [#assign sharedCount = 0]
                    [#list sharedComponents as component] 
                        [#if component.S3??]
                            [#assign s3 = component.S3]
                            [#if sharedCount > 0],[/#if]        
                            "s3XproductX${component.Id}" : {
                                "Value" : { "Ref" : "s3X${component.Id}" }
                            }
                            [#assign sharedCount = sharedCount + 1]
                    [/#if]
                    [/#list]
                    [#assign sliceCount = sliceCount + 1]
                [/#if]
            [/#if]
        [/#if]
    }
}
