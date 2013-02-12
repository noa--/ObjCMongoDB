//
//  MongoDBCollection.m
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

#import "MongoDBCollection.h"
#import "MongoConnection.h"
#import "mongo.h"
#import "BSONDocument.h"
#import "BSONEncoder.h"
#import "BSON_Helper.h"
#import "MongoFindRequest.h"
#import "MongoUpdateRequest.h"
#import "Mongo_PrivateInterfaces.h"
#import "Mongo_Helper.h"

@implementation MongoDBCollection {
    NSString *_name;
}

#pragma mark - Initialization

- (void) dealloc {
#if !__has_feature(objc_arc)
    [_name release];
    [super dealloc];
#endif
}

- (void) setName:(NSString *) value {
    _name = [value copy];
    NSRange firstDot = [value rangeOfString:@"."];
    if (NSNotFound == firstDot.location) {
        id exc = [NSException exceptionWithName:NSInvalidArgumentException
                                         reason:@"Collection name is missing database component (e.g. db.person)"
                                       userInfo:nil];
        @throw exc;
    }
    self.databaseName = [value substringToIndex:firstDot.location];
    self.namespaceName = [value substringFromIndex:1+firstDot.location];
}

#pragma mark - Insert

- (BOOL) insertDocument:(BSONDocument *) document
           writeConcern:(MongoWriteConcern *) writeConcern
                  error:(NSError * __autoreleasing *) error {
    if (MONGO_OK == mongo_insert(self.connection.connValue,
                                 self.utf8Name,
                                 document.bsonValue,
                                 [[self _coalesceWriteConcern:writeConcern] nativeWriteConcern]))
        return YES;
    else
        set_error_and_return_NO;
}

- (BOOL) insertDictionary:(NSDictionary *) dictionary
             writeConcern:(MongoWriteConcern *) writeConcern
                    error:(NSError * __autoreleasing *) error {
    BSONDocument *document = [BSONEncoder documentForDictionary:dictionary];
    return [self insertDocument:document writeConcern:writeConcern error:error];
}

- (BOOL) insertObject:(id) object
         writeConcern:(MongoWriteConcern *) writeConcern
                error:(NSError * __autoreleasing *) error {
    BSONDocument *document = [BSONEncoder documentForObject:object];
    return [self insertDocument:document writeConcern:writeConcern error:error];
}

- (BOOL) insertDocuments:(NSArray *) documentArray
         continueOnError:(BOOL) continueOnError
            writeConcern:(MongoWriteConcern *) writeConcern
                   error:(NSError * __autoreleasing *) error {
    if (documentArray.count > INT_MAX)
        [NSException raise:NSInvalidArgumentException
                    format:@"That's a lot of documents! Keep it to %i",
         INT_MAX];

    int documentsToInsert = (int) documentArray.count;
    const bson *bsonArray[documentsToInsert];
    const bson **current = bsonArray;
    for (__strong BSONDocument *document in documentArray) {
        if(![document isKindOfClass:[BSONDocument class]]) {
            document = [BSONEncoder documentForObject:document];
        }
        *current++ = document.bsonValue;
    }
    int flags = continueOnError ? MONGO_CONTINUE_ON_ERROR : 0;
    if (MONGO_OK == mongo_insert_batch(self.connection.connValue,
                                       self.utf8Name,
                                       bsonArray,
                                       documentsToInsert,
                                       [[self _coalesceWriteConcern:writeConcern] nativeWriteConcern],
                                       flags))
        return YES;
    else
        set_error_and_return_NO;
}

#pragma mark - Update

- (BOOL) updateWithRequest:(MongoUpdateRequest *) updateRequest
                     error:(NSError * __autoreleasing *) error {
    if (MONGO_OK == mongo_update(self.connection.connValue,
                                 self.utf8Name,
                                 updateRequest.conditionDocumentValue.bsonValue,
                                 updateRequest.operationDocumentValue.bsonValue,
                                 updateRequest.flags,
                                 [[self _coalesceWriteConcern:updateRequest.writeConcern] nativeWriteConcern]))
        return YES;
    else
        set_error_and_return_NO;
}

#pragma mark - Remove

- (BOOL) removeWithPredicate:(MongoPredicate *) predicate
                writeConcern:(MongoWriteConcern *) writeConcern
                       error:(NSError * __autoreleasing *) error {
    if (!predicate)
        [NSException raise:NSInvalidArgumentException
                    format:@"For safety, remove with nil predicate is not allowed - use removeAllWithWriteConcern:error: instead"];
    return [self _removeWithCond:predicate.BSONDocument
                    writeConcern:writeConcern
                           error:error];
}

- (BOOL) removeAllWithWriteConcern:(MongoWriteConcern *) writeConcern
                             error:(NSError * __autoreleasing *) error {
    BSONDocument *document = [[BSONDocument alloc] init];
#if !__has_feature(objc_arc)
    [document autorelease];
#endif
    return [self _removeWithCond:document
                    writeConcern:writeConcern
                           error:error];
}

- (BOOL) _removeWithCond:(BSONDocument *) cond
            writeConcern:(MongoWriteConcern *) writeConcern
                   error:(NSError * __autoreleasing *) error {
    int result = mongo_remove(self.connection.connValue,
                              self.utf8Name,
                              cond.bsonValue,
                              [[self _coalesceWriteConcern:writeConcern] nativeWriteConcern]);
    if (MONGO_OK == result)
        return YES;
    else
        set_error_and_return_NO;
}

#pragma mark - Find

- (NSArray *) findWithRequest:(MongoFindRequest *) findRequest
                        error:(NSError * __autoreleasing *) error {
    return [[self cursorForFindRequest:findRequest error:error] allObjects];
}

- (MongoCursor *) cursorForFindRequest:(MongoFindRequest *) findRequest
                                 error:(NSError * __autoreleasing *) error {
    mongo_cursor *cursor = mongo_find(self.connection.connValue, self.utf8Name,
                                      findRequest.queryDocument.bsonValue,
                                      findRequest.fieldsDocument.bsonValue,
                                      findRequest.limitResults,
                                      findRequest.skipResults,
                                      findRequest.options);
    if (!cursor) set_error_and_return_nil;
    return [MongoCursor cursorWithNativeCursor:cursor];
}

- (BSONDocument *) findOneWithRequest:(MongoFindRequest *) findRequest
                                error:(NSError * __autoreleasing *) error {
    bson *tempBson = bson_create();
    int result = mongo_find_one(self.connection.connValue, self.utf8Name,
                                findRequest.queryDocument.bsonValue,
                                findRequest.fieldsDocument.bsonValue,
                                tempBson);
    if (BSON_OK != result) {
        bson_dispose(tempBson);
        set_error_and_return_nil;
    }
    bson *newBson = bson_create();
    bson_copy(newBson, tempBson);
    bson_dispose(tempBson);
    return [BSONDocument documentWithNativeDocument:newBson destroyWhenDone:YES];
}

- (NSArray *) findWithPredicate:(MongoPredicate *) predicate
                          error:(NSError * __autoreleasing *) error {
    return [[self cursorForFindWithPredicate:predicate error:error] allObjects];
}

- (MongoCursor *) cursorForFindWithPredicate:(MongoPredicate *) predicate
                                       error:(NSError * __autoreleasing *) error {
    return [self cursorForFindRequest:[MongoFindRequest findRequestWithPredicate:predicate] error:error];
}

- (BSONDocument *) findOneWithPredicate:(MongoPredicate *) predicate
                                  error:(NSError * __autoreleasing *) error {
    return [self findOneWithRequest:[MongoFindRequest findRequestWithPredicate:predicate] error:error];
}

- (NSArray *) findAllWithError:(NSError * __autoreleasing *) error {
    return [[self cursorForFindAllWithError:error] allObjects];
}

- (MongoCursor *) cursorForFindAllWithError:(NSError * __autoreleasing *) error {
    return [self cursorForFindWithPredicate:[MongoPredicate predicate] error:error];
}

- (BSONDocument *) findOneWithError:(NSError * __autoreleasing *) error {
    return [self findOneWithPredicate:[MongoPredicate predicate] error:error];
}

- (NSUInteger) countWithPredicate:(MongoPredicate *) predicate
                            error:(NSError * __autoreleasing *) error {
    if (!predicate) predicate = [MongoPredicate predicate];
    NSUInteger result = mongo_count(self.connection.connValue,
                                    self.utf8DatabaseName, self.utf8NamespaceName,
                                    predicate.BSONDocument.bsonValue);
    if (BSON_ERROR == result) set_error_and_return_BSON_ERROR;
    return result;
}

#pragma mark - Create indexes

//int mongo_create_index( mongo *conn, const char *ns, bson *key, int options, bson *out );
//bson_bool_t mongo_create_simple_index( mongo *conn, const char *ns, const char *field, int options, bson *out );

#pragma mark - Administration

- (BOOL) dropCollectionWithError:(NSError *__autoreleasing *) outError {
    NSError *error = nil;
    NSDictionary *command = @{ @"drop" : self.namespaceName };
    [self.connection runCommandWithDictionary:command
                               onDatabaseName:self.databaseName
                                        error:&error];
    if (error) {
        if (outError) *outError = error;
        return NO;
    } else
        return YES;
}

#pragma mark - Helper methods

- (MongoWriteConcern *) _coalesceWriteConcern:(MongoWriteConcern *) writeConcern {
    return writeConcern ? writeConcern : self.connection.writeConcern;
}

- (BOOL) lastOperationWasSuccessful:(NSError * __autoreleasing *) error {
    return [self.connection lastOperationWasSuccessful:error];
}
- (NSDictionary *) lastOperationDictionary {
    return [self.connection lastOperationDictionary];
}
- (NSError *) error {
    return [self.connection error];
}
- (NSError *) serverError {
    return [self.connection serverError];
}

#pragma mark - Accessors

- (const char *) utf8Name { return self.name.bsonString; }
- (const char *) utf8DatabaseName { return self.databaseName.bsonString; }
- (const char *) utf8NamespaceName { return self.namespaceName.bsonString; }

@end