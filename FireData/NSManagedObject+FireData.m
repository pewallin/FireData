//
//  NSManagedObject+Firebase.m
//  Firebase
//
//  Created by Jonathan Younger on 2/26/13.
//  Copyright (c) 2013 Overcommitted, LLC. All rights reserved.
//

#import "NSManagedObject+FireData.h"
#import "FireDataISO8601DateFormatter.h"

#define FirebaseSyncData [[NSUUID UUID] UUIDString]
static NSString * const kFireDataDeletedValue = @"";

@implementation NSManagedObject (FireData)

- (NSDictionary *)firedata_changedAttributesWithCoreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute
{
    NSMutableDictionary *changedAttributes = [[NSMutableDictionary alloc] init];
    FireDataISO8601DateFormatter *dateFormatter = [FireDataISO8601DateFormatter sharedFormatter];
    
    NSDictionary *propertiesByName = [[self entity] propertiesByName];
    NSDictionary *changedValues = [self changedValues];
    [changedValues enumerateKeysAndObjectsUsingBlock:^(NSString *name, id value, BOOL *stop) {
        if ([name isEqualToString:coreDataKeyAttribute] || [name isEqualToString:coreDataDataAttribute]) return;
        
        NSPropertyDescription *property = [propertiesByName objectForKey:name];
        if ([property isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeDescription *attributeDescription = (NSAttributeDescription *)property;
            if (![attributeDescription isTransient]) {
                NSAttributeType attributeType = [attributeDescription attributeType];
                if ((attributeType == NSDateAttributeType) && ([value isKindOfClass:[NSDate class]]) && (dateFormatter != nil)) {
                    [changedAttributes setValue:[dateFormatter stringFromDate:value] forKey:name];
                } else {
                    [changedAttributes setValue:value forKey:name];
                }
            }
        } else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            if (![(NSRelationshipDescription *)property isToMany]) {
                [changedAttributes setValue:[value valueForKey:coreDataKeyAttribute] forKey:name];
            }
        }
    }];
    
    return [[NSDictionary alloc] initWithDictionary:changedAttributes];
}

- (NSDictionary *)firedata_changedRelationshipsWithCoreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute
{
    NSMutableDictionary *changedRelationships = [[NSMutableDictionary alloc] init];
    
    NSDictionary *propertiesByName = [[self entity] propertiesByName];
    NSDictionary *changedValues = [self changedValues];
    NSDictionary *committedValues = [self committedValuesForKeys:[changedValues allKeys]];
    [changedValues enumerateKeysAndObjectsUsingBlock:^(NSString *name, id value, BOOL *stop) {
        if ([name isEqualToString:coreDataKeyAttribute] || [name isEqualToString:coreDataDataAttribute]) return;
        
        NSPropertyDescription *property = [propertiesByName objectForKey:name];
        if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            if ([(NSRelationshipDescription *)property isToMany]) {
                NSMutableDictionary *items = [[NSMutableDictionary alloc] init];
                NSSet *oldItems = [[NSSet alloc] initWithSet:[committedValues objectForKey:name]];
                NSSet *currentItems = [[NSSet alloc] initWithSet:value];
                
                for (NSManagedObject *managedObject in oldItems) {
                    if (![currentItems containsObject:managedObject]) {
                        NSString *identifier = [managedObject valueForKey:coreDataKeyAttribute];
                        if (identifier) {
                            [items setValue:kFireDataDeletedValue forKey:identifier];
                        }
                    }
                }
                
                for (NSManagedObject *managedObject in currentItems) {
                    if (![oldItems containsObject:managedObject]) {
                        NSString *identifier = [managedObject valueForKey:coreDataKeyAttribute];
                        if (identifier) {
                            [items setValue:identifier forKey:identifier];
                        }
                    }
                }
                
                [changedRelationships setValue:items forKey:name];
            }
        }
    }];

    return [[NSDictionary alloc] initWithDictionary:changedRelationships];
}

- (void)firedata_setPropertiesForKeysWithDictionary:(NSDictionary *)keyedValues coreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute
{
    FireDataISO8601DateFormatter *dateFormatter = [FireDataISO8601DateFormatter sharedFormatter];
    for (NSPropertyDescription *propertyDescription in [[self entity] properties]) {
        NSString *name = [propertyDescription name];
        if ([name isEqualToString:coreDataKeyAttribute] || [name isEqualToString:coreDataDataAttribute]) continue;
        
        if ([propertyDescription isKindOfClass:[NSAttributeDescription class]]) {
            id value = [keyedValues objectForKey:name];
            
            NSAttributeType attributeType = [(NSAttributeDescription *)propertyDescription attributeType];
            if ((attributeType == NSStringAttributeType) && ([value isKindOfClass:[NSNumber class]])) {
                value = [value stringValue];
            } else if (((attributeType == NSInteger16AttributeType) || (attributeType == NSInteger32AttributeType) || (attributeType == NSInteger64AttributeType) || (attributeType == NSBooleanAttributeType)) && ([value isKindOfClass:[NSString class]])) {
                value = [NSNumber numberWithInteger:[value integerValue]];
            } else if ((attributeType == NSFloatAttributeType) && ([value isKindOfClass:[NSString class]])) {
                value = [NSNumber numberWithDouble:[value doubleValue]];
            } else if ((attributeType == NSDateAttributeType) && ([value isKindOfClass:[NSString class]]) && (dateFormatter != nil)) {
                value = [dateFormatter dateFromString:value];
            }
            
            [self setValue:value forKey:name];
        } else if ([propertyDescription isKindOfClass:[NSRelationshipDescription class]]) {
            NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[[(NSRelationshipDescription *)propertyDescription destinationEntity] name]];
            [fetchRequest setFetchLimit:1];
            
            if ([(NSRelationshipDescription *)propertyDescription isToMany]) {
                NSMutableSet *items = [self mutableSetValueForKey:name];
                NSDictionary *identifiers = [keyedValues objectForKey:name];
                
                [identifiers enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, id value, BOOL *stop) {
                    if ([value isEqualToString:kFireDataDeletedValue]) {
                        NSManagedObject *managedObject = [[items filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"%K == %@", coreDataKeyAttribute, identifier]] anyObject];
                        if (managedObject) {
                            [items removeObject:managedObject];
                        }
                    } else {
                        [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", coreDataKeyAttribute, identifier]];
                        NSArray *objects = [self.managedObjectContext executeFetchRequest:fetchRequest error:nil];
                        if ([objects count] == 1) {
                            NSManagedObject *managedObject = objects[0];
                            if (![items containsObject:managedObject]) {
                                [managedObject setValue:FirebaseSyncData forKey:coreDataDataAttribute];
                                [items addObject:managedObject];
                            }
                        }
                    }
                }];
            } else {
                NSString *identifier = [keyedValues objectForKey:name];
                
                NSManagedObject *managedObject = [self valueForKey:name];
                NSString *managedObjectIdentifier = [managedObject valueForKey:coreDataKeyAttribute];
                if (managedObjectIdentifier && ![identifier isEqualToString:managedObjectIdentifier]) {
                    [managedObject setValue:FirebaseSyncData forKey:coreDataDataAttribute];
                }
                
                if (identifier) {
                    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", coreDataKeyAttribute, identifier]];
                    NSArray *objects = [self.managedObjectContext executeFetchRequest:fetchRequest error:nil];
                    if ([objects count] == 1) {
                        NSManagedObject *managedObject = objects[0];
                        if (![[self valueForKey:name] isEqual:managedObject]) {
                            [managedObject setValue:FirebaseSyncData forKey:coreDataDataAttribute];
                            [self setValue:managedObject forKey:name];
                        }
                    }
                } else {
                    [self setValue:nil forKey:name];
                }
            }
        }
    }
    
    if ([[self changedValues] count] > 0) {
        [self setValue:FirebaseSyncData forKey:coreDataDataAttribute];
    }
}
@end
