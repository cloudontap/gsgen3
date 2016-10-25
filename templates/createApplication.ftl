[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = (credentials?eval).Credentials]
[#assign appSettingsObject = appsettings?eval]
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
[#assign accountRegionObject = regions[accountRegion]]
[#assign productRegionObject = regions[productRegion]]
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
[#assign accountRegionId = accountRegionObject.Id]
[#assign productRegionId = productRegionObject.Id]
[#assign environmentId = environmentObject.Id]
[#assign environmentName = environmentObject.Name]
[#assign categoryId = categoryObject.Id]

[#-- Domains --]
[#assign segmentDomain = getKey("domainXsegmentXdomain")]
[#assign segmentDomainQualifier = getKey("domainXsegmentXqualifier")]

[#-- Buckets --]
[#assign credentialsBucket = getKey("s3XaccountXcredentials")!"unknown"]
[#assign codeBucket = getKey("s3XaccountXcode")!"unknown"]
[#assign logsBucket = getKey("s3XsegmentXlogs")]
[#assign backupsBucket = getKey("s3XsegmentXbackups")]

[#-- AZ List --]
[#assign azList = segmentObject.AZList]

[#-- Loop optimisation --]
[#assign lastTier = solutionTiers?last]
[#assign firstZone = azList?first]
[#assign lastZone = azList?last]
[#assign zoneCount = azList?size]

[#-- Get stack output --]
[#function getKey key]
    [#list stackOutputsObject as pair]
        [#if pair.OutputKey==key]
            [#return pair.OutputValue]
        [/#if]
    [/#list]
[/#function]

[#-- Application --]
[#assign docker = appSettingsObject.Docker]
[#assign solnMultiAZ = solutionObject.MultiAZ!environmentObject.MultiAZ!false]

[#if buildReference??]
    [#assign buildCommit = buildReference]
    [#assign buildSeparator = buildReference?index_of(" ")]
    [#if buildSeparator != -1]
        [#assign buildCommit = buildReference[0..(buildSeparator-1)]]
        [#assign appReference = buildReference[(buildSeparator+1)..]]
    [/#if]
[/#if]

[#macro standardEnvironmentVariables]
    {
        "Name" : "TEMPLATE_TIMESTAMP",
        "Value" : "${.now?iso_utc}"
    },
    {
        "Name" : "ENVIRONMENT",
        "Value" : "${environmentName}"
    }
    [#if configurationReference??]
        ,{
            "Name" : "CONFIGURATION_REFERENCE",
            "Value" : "${configurationReference}"
        }
    [/#if]
    [#if buildCommit??]
        ,{
            "Name" : "BUILD_REFERENCE",
            "Value" : "${buildCommit}"
        }
    [/#if]
    [#if appReference?? && (appReference != "")]
        ,{
            "Name" : "APP_REFERENCE",
            "Value" : "${appReference}"
        }
    [/#if]
[/#macro]

[#macro createTask tier component task]
    "ecsTaskX${tier.Id}X${component.Id}X${task.Id}" : {
        "Type" : "AWS::ECS::TaskDefinition",
        "Properties" : {
            "ContainerDefinitions" : [
                [#list task.Containers as container]
                    [#assign dockerTag = ""]
                    [#if container.Version??]
                        [#assign dockerTag = ":" + container.Version]
                    [/#if]
                    {
                        [#assign containerListMode = "definition"]
                        [#include containerList]
                        "Memory" : "${container.Memory?c}",
                        "Cpu" : "${container.Cpu?c}",
                        [#if container.Ports??]
                            "PortMappings" : [
                                [#list container.Ports as port]
                                    {
                                        [#if port.Container??]
                                            "ContainerPort" : ${ports[port.Container].Port?c},
                                        [#else]
                                            "ContainerPort" : ${ports[port.Id].Port?c},
                                        [/#if]
                                        "HostPort" : ${ports[port.Id].Port?c}
                                    }[#if !(port.Id == (container.Ports?last).Id)],[/#if]
                                [/#list]
                            ],
                        [/#if]
                        "LogConfiguration" : {
                            [#if (docker.LocalLogging?? && (docker.LocalLogging == true)) || (container.LocalLogging?? && (container.LocalLogging == true))]
                                "LogDriver" : "json-file"
                            [#else]
                                "LogDriver" : "fluentd",
                                "Options" : { "tag" : "docker.${productId}.${segmentId}.${tier.Id}.${component.Id}.${container.Id}"}
                            [/#if]
                        }
                    }[#if container.Id != (task.Containers?last).Id],[/#if]
                [/#list]
            ]
            [#assign volumeCount = 0]
            [#list task.Containers as container]
                [#assign containerListMode = "volumeCount"]
                [#include containerList]
            [/#list]
            [#if volumeCount > 0]
                ,"Volumes" : [
                    [#assign volumeCount = 0]
                    [#list task.Containers as container]
                        [#assign containerListMode = "volumes"]
                        [#include containerList]
                    [/#list]
                ]
            [/#if]
        }
    }
[/#macro]
{
    "AWSTemplateFormatVersion" : "2010-09-09",
    "Resources" : 
    {
        [#assign count = 0]
        [#list solutionTiers as solutionTier]
            [#assign tier = tiers[solutionTier.Id]]
            [#if solutionTier.Components??]
                [#list solutionTier.Components as component]
                    [#assign slices = component.Slices!solutionTier.Slices!tier.Slices]
                    [#if slices?seq_contains(slice)]
                        [#if component.MultiAZ??] 
                            [#assign multiAZ =  component.MultiAZ]
                        [#else]
                            [#assign multiAZ =  solnMultiAZ]
                        [/#if]
                        [#-- ECS --]
                        [#if component.ECS??]
                            [#assign ecs = component.ECS]
                            [#assign fixedIP = ecs.FixedIP?? && ecs.FixedIP]
                            [#assign ecsSG = getKey("securityGroupX" + tier.Id + "X" + component.Id) ]
                            [#if ecs.Services??]
                                [#list ecs.Services as service]
                                    [#assign serviceSlices = service.Slices!component.Slices!solutionTier.Slices!tier.Slices]
                                    [#if serviceSlices?seq_contains(slice)]
                                        [#if count > 0],[/#if]
                                        [#assign targetGroupName = service.Id]
                                        [@createTask tier=tier component=component task=service /]
                                        ,"ecsServiceX${tier.Id}X${component.Id}X${service.Id}" : {
                                            "Type" : "AWS::ECS::Service",
                                            "Properties" : {
                                                "Cluster" : "${getKey("ecsX" + tier.Id + "X" + component.Id)}",
                                                "DeploymentConfiguration" : {
                                                    [#if multiAZ]
                                                        "MaximumPercent" : 100,
                                                        "MinimumHealthyPercent" : 50
                                                    [#else]
                                                        "MaximumPercent" : 100,
                                                        "MinimumHealthyPercent" : 0
                                                    [/#if]
                                                },
                                                [#if service.DesiredCount??]
                                                    "DesiredCount" : "${service.DesiredCount}",
                                                [#else]
                                                    "DesiredCount" : "${multiAZ?string(zoneCount,"1")}",
                                                [/#if]
                                                [#assign portCount = 0]
                                                [#list service.Containers as container]
                                                    [#if container.Ports??]
                                                        [#list container.Ports as port]
                                                            [#if port.ELB??]
                                                                [#assign portCount = portCount + 1]
                                                                [#break]
                                                            [/#if]
                                                        [/#list]
                                                    [/#if]
                                                [/#list]
                                                [#if portCount != 0]
                                                    "LoadBalancers" : [
                                                        [#assign portCount = 0]
                                                        [#list service.Containers as container]
                                                            [#if container.Ports??]
                                                                [#list container.Ports as port]
                                                                    [#if port.ELB??]
                                                                        [#if portCount > 0],[/#if]
                                                                        {
                                                                            "LoadBalancerName" : "${getKey("elbXelbX" + port.ELB)}",
                                                                            "ContainerName" : "${tier.Name + "-" + component.Name + "-" + container.Id}",
                                                                            [#if port.Container??]
                                                                                "ContainerPort" : ${ports[port.Container].Port?c}
                                                                            [#else]
                                                                                "ContainerPort" : ${ports[port.Id].Port?c}
                                                                            [/#if]
                                                                        }
                                                                        [#assign portCount = portCount + 1]
                                                                        [#break]
                                                                    [/#if]
                                                                [/#list]
                                                            [/#if]
                                                        [/#list]
                                                    ],
                                                    "Role" : "${getKey("roleX" + tier.Id + "X" + component.Id + "Xservice")}",
                                                [/#if]
                                                "TaskDefinition" : { "Ref" : "ecsTaskX${tier.Id}X${component.Id}X${service.Id}" }
                                            }
                                        }
                                        [#list service.Containers as container]
                                            [#-- Supplemental definitions for the container --] 
                                            [#assign containerListMode = "supplemental"]
                                            [#include containerList]

                                            [#-- Security Group ingress for the service ports --] 
                                            [#if container.Ports??]
                                                [#list container.Ports as port]
                                                    [#if port?is_hash]
                                                        [#assign portId = port.Id]
                                                        [#assign fromSG = port.ELB?? && 
                                                            ((port.limitAccessToSG?? && port.limitAccessToSG) || fixedIP)]
                                                        [#if fromSG]
                                                            [#assign elbSG = getKey("securityGroupXelbX"+port.ELB)]
                                                        [/#if]
                                                    [#else]
                                                        [#assign portId = port]
                                                        [#assign fromSG = false]
                                                    [/#if]
                                                    "securityGroupIngressX${tier.Id}X${component.Id}X${ports[portId].Port?c}" : {
                                                        "Type" : "AWS::EC2::SecurityGroupIngress",
                                                        "Properties" : {
                                                            "GroupId": ${ecsSG},
                                                            "IpProtocol": "${ports[portId].IPProtocol}", 
                                                            "FromPort": "${ports[portId].Port?c}", 
                                                            "ToPort": "${ports[portId].Port?c}", 
                                                            [#if fromSG]
                                                                "SourceSecurityGroupId": "${elbSG}"
                                                            [#else]
                                                                "CidrIp": "0.0.0.0/0"
                                                            [/#if]
                                                        }
                                                    },
                                                [/#list]
                                            [/#if]
                                            [#if container.PortMappings??]
                                                [#list container.PortMappings as mapping]
                                                    [#assign destination = ports[portMappings[mapping.Id].Destination]]
                                                    [#assign useDynamicHostPort = mapping.DynamicHostPort?? && mapping.DynamicHostPort]
                                                    [#assign targetGroupName = service.Id + "X" + container.Id]
                                                    [#if mapping.targetGroup??]
                                                        [#assign targetGroupName = mapping.targetGroup]
                                                    [/#if]
                                                    [#if useDynamicHostPort]
                                                        [#assign ruleName = targetGroupName + "Xdynamic"]
                                                    [#else]
                                                        [#assign ruleName = targetGroupName + "X" + destination.Port?c]
                                                    [/#if]
                                                    [#assign fromSG = (mapping.ELB?? || mapping.ILB??) && 
                                                        ((mapping.limitAccessToSG?? && mapping.limitAccessToSG) || fixedIP)]
                                                    [#if fromSG]
                                                        [#if mapping.ELB??]
                                                            [#assign elbSG = getKey("securityGroupXelbX"+mapping.ELB)]
                                                        [#else]
                                                            [#assign elbSG = getKey("securityGroupXilbX"+mapping.ILB)]
                                                        [/#if]
                                                    [/#if]
                                                    "securityGroupIngressX${tier.Id}X${component.Id}X${ruleName}" : {
                                                        "Type" : "AWS::EC2::SecurityGroupIngress",
                                                        "Properties" : {
                                                            "GroupId": ${ecsSG},
                                                            "IpProtocol": "${destination.IPProtocol}",
                                                            [#if useDynamicHostPort]
                                                                "FromPort": "49153",
                                                                "ToPort": "65535",
                                                            [#else]
                                                                "FromPort": "${destination.Port?c}", 
                                                                "ToPort": "${destination.Port?c}", 
                                                            [/#if]
                                                            [#if fromSG]
                                                                "SourceSecurityGroupId": "${elbSG}"
                                                            [#else]
                                                                "CidrIp": "0.0.0.0/0"
                                                            [/#if]
                                                        }
                                                    },
                                                [/#list]
                                            [/#if]
                                        [/#list]
                                        [#assign count = count + 1]
                                    [/#if]
                                [/#list]
                            [/#if]
                            [#if ecs.Tasks??]
                                [#list ecs.Tasks as task]
                                    [#assign taskSlices = task.Slices!component.Slices!solutionTier.Slices!tier.Slices]
                                    [#if taskSlices?seq_contains(slice)]
                                        [#if count > 0],[/#if]
                                        [@createTask tier=tier component=component task=task /]
                                        [#list task.Containers as container]
                                            [#assign containerListMode = "supplemental"]
                                            [#include containerList]
                                        [/#list]
                                        [#assign count = count + 1]
                                    [/#if]
                                [/#list]
                            [/#if]
                        [/#if]
                    [/#if]
                [/#list]
            [/#if]
        [/#list]
    },
    "Outputs" : 
    {
        [#assign count = 0]
        [#list solutionTiers as solutionTier]
            [#assign tier = tiers[solutionTier.Id]]
            [#if solutionTier.Components??]
                [#list solutionTier.Components as component]
                    [#assign slices = component.Slices!solutionTier.Slices!tier.Slices]
                    [#if slices?seq_contains(slice)]
                        [#-- ECS --]
                        [#if component.ECS??]
                            [#assign ecs = component.ECS]
                            [#if ecs.Services??]
                                [#list ecs.Services as service]
                                    [#assign serviceSlices = service.Slices!component.Slices!solutionTier.Slices!tier.Slices]
                                    [#if serviceSlices?seq_contains(slice)]
                                        [#if count > 0],[/#if]
                                            "ecsServiceX${tier.Id}X${component.Id}X${service.Id}" : {
                                                "Value" : { "Ref" : "ecsServiceX${tier.Id}X${component.Id}X${service.Id}" }
                                            },
                                            "ecsTaskX${tier.Id}X${component.Id}X${service.Id}" : {
                                                "Value" : { "Ref" : "ecsTaskX${tier.Id}X${component.Id}X${service.Id}" }
                                            }
                                            [#assign count = count + 1]
                                    [/#if]
                                [/#list]
                            [/#if]
                            [#if ecs.Tasks??]
                                [#list ecs.Tasks as task]
                                    [#assign taskSlices = task.Slices!component.Slices!solutionTier.Slices!tier.Slices]
                                    [#if taskSlices?seq_contains(slice)]
                                        [#if count > 0],[/#if]
                                            "ecsTaskX${tier.Id}X${component.Id}X${task.Id}" : {
                                                "Value" : { "Ref" : "ecsTaskX${tier.Id}X${component.Id}X${task.Id}" }
                                            }
                                            [#assign count = count + 1]
                                    [/#if]
                                [/#list]
                            [/#if]
                        [/#if]
                    [/#if]
                [/#list]
            [/#if]
        [/#list]
    }
}

