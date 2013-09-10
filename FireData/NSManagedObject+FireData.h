//
//  NSManagedObject+Firebase.h
//  Firebase
//
//  Created by Jonathan Younger on 2/26/13.
//  Copyright (c) 2013 Overcommitted, LLC. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (FireData)
- (NSDictionary *)firedata_changedAttributesWithCoreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute;
- (NSDictionary *)firedata_changedRelationshipsWithCoreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute;
- (void)firedata_setPropertiesForKeysWithDictionary:(NSDictionary *)keyedValues coreDataKeyAttribute:(NSString *)coreDataKeyAttribute coreDataDataAttribute:(NSString *)coreDataDataAttribute;
@end
