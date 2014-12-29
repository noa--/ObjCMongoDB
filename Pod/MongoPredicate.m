//
//  MongoPredicate.m
//  ObjCMongoDB
//
//  Copyright 2012 Paul Melnikow and other contributors
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "MongoPredicate.h"
#import "ObjCMongoDB.h"
#import "Helper-private.h"
#import <BSONSerializer.h>

@interface MongoPredicate ()
@property (retain) MutableOrderedDictionary *dictionary;
@property (retain) NSString *operator;
@end

@implementation MongoPredicate

- (id) init {
    if (self = [super init]) {
        self.dictionary = [MutableOrderedDictionary dictionary];
    }
    return self;
}

- (id) initWithOperator:(NSString *) operator subPredicates:(NSArray *) subPredicates {
    if (self = [self init]) {
        self.operator = operator;
        NSMutableArray *dictionaries = [NSMutableArray array];
        for (MongoPredicate *predicate in subPredicates)
            [dictionaries addObject:predicate.dictionary];
        [self.dictionary setObject:dictionaries forKey:operator];
    }
    return self;
}

+ (MongoPredicate *) predicate {
    return [[self alloc] init];
}

#pragma mark - Getting the result

- (BSONDocument *) BSONDocument {
    BSONSerializer *serializer = [BSONSerializer serializer];
    if (! [serializer serializeDictionary:self.dictionary error:nil])
        [NSException raise:NSInternalInconsistencyException format:@"Unable to serialize predicate dictionary"];
    
    return [serializer document];
}

- (NSString *) description {
    NSString *identifier = [NSString stringWithFormat:@"%@ <%p>\n", [[self class] description], self];
    return [identifier stringByAppendingFormat:@"%@", [self dictionary]];
}

#pragma mark - Or, nor, and predicates - Intitialization

+ (MongoPredicate *) orPredicateWithSubPredicate:(MongoPredicate *) predicate {
    return [self orPredicateWithArray:[NSArray arrayWithObject:predicate]];
}

+ (MongoPredicate *) orPredicateWithSubPredicates:(MongoPredicate *) predicate, ... {
    NSMutableArray *objects = [NSMutableArray array];
    va_addToNSMutableArray(predicate, objects);
    return [self orPredicateWithArray:objects];
}

+ (MongoPredicate *) orPredicateWithArray:(NSArray *) array {
    return [[self alloc] initWithOperator:@"$or" subPredicates:array];
}

+ (MongoPredicate *) norPredicateWithSubPredicate:(MongoPredicate *) predicate {
    return [self norPredicateWithArray:[NSArray arrayWithObject:predicate]];
}

+ (MongoPredicate *) norPredicateWithSubPredicates:(MongoPredicate *) predicate, ... {
    NSMutableArray *objects = [NSMutableArray array];
    va_addToNSMutableArray(predicate, objects);
    return [self norPredicateWithArray:objects];
}

+ (MongoPredicate *) norPredicateWithArray:(NSArray *) array {
    return [[self alloc] initWithOperator:@"$nor" subPredicates:array];
}

+ (MongoPredicate *) andPredicateWithSubPredicate:(MongoPredicate *) predicate {
    return [self andPredicateWithArray:[NSArray arrayWithObject:predicate]];
}

+ (MongoPredicate *) andPredicateWithSubPredicates:(MongoPredicate *) predicate, ... {
    NSMutableArray *objects = [NSMutableArray array];
    va_addToNSMutableArray(predicate, objects);
    return [self andPredicateWithArray:objects];
}

+ (MongoPredicate *) andPredicateWithArray:(NSArray *) array {
    return [[self alloc] initWithOperator:@"$and" subPredicates:array];
}

#pragma mark - And and Or predicates - Mutability and convenience

- (void) addSubPredicate:(MongoPredicate *) predicate {
    [(NSMutableArray *) [self.dictionary objectForKey:self.operator] addObject:predicate.dictionary];
}

- (MongoKeyedPredicate *) addKeyedSubPredicate {
    id subPredicate = [MongoKeyedPredicate predicate];
    [self addSubPredicate:subPredicate];
    return subPredicate;
}

#pragma mark - Where predicate

- (id) initWithWhereExpression:(BSONCode *) whereExpression {
    if (self = [self init]) {
        [self.dictionary setObject:whereExpression forKey:@"$where"];
    }
    return self;
}

+ (MongoPredicate *) wherePredicateWithExpression:(BSONCode *) whereExpression {
    return [[self alloc] initWithWhereExpression:whereExpression];
}

@end
