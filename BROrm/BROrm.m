//
//  BROrm.m
//  BROrm
//
//  Created by Cornelius Horstmann on 15.06.13.
//  Copyright (c) 2013 brototyp.de. All rights reserved.
//

#import "BROrm.h"
#import "FMDatabase.h"
#import "FMDatabaseQueue.h"


@interface BROrm(){
    BOOL _isNew;
    
    NSMutableDictionary *_data;
    NSMutableArray *_dirtyFields;
    
    BOOL _isRawQuery;
    NSString *_rawQuery;
    NSArray *_rawParameters;
    
    NSArray *_parameters; //former values
    NSMutableArray *_columns;
    
    NSMutableArray *_whereConditions;
    NSMutableArray *_joins;
    NSMutableArray *_orders;
}


- (BOOL)saveInTransaction:(FMDatabase *)database;

@end

static FMDatabaseQueue *_defaultQueue = NULL;
static NSString *_idColumn = @"identifier";

@implementation BROrm

- (id)init{
    self = [super init];
    if(self){
        _columns = [NSMutableArray array];
        _whereConditions = [NSMutableArray array];
        _joins = [NSMutableArray array];
        _orders = [NSMutableArray array];
        _dirtyFields = [NSMutableArray array];
    }
    return self;
}

+ (instancetype)forTable:(NSString*)tableName{
    if(!_defaultQueue) return NULL;
    return [self forTable:tableName inDatabase:_defaultQueue];
}
+ (instancetype)forTable:(NSString*)tableName inDatabase:(FMDatabaseQueue*)databaseQueue{
    BROrm *orm = [[BROrm alloc] init];
    if(orm){
        orm.tableName = tableName;
        orm.databaseQueue = databaseQueue;
    }
    return orm;
}

+ (NSArray *)executeQuery:(NSString*)query withArgumentsInArray:(NSArray*)arguments{
    if(!_defaultQueue) return NULL;
    return [self executeQuery:query withArgumentsInArray:arguments inDatabaseQueue:_defaultQueue];
}

+ (NSArray *)executeQuery:(NSString*)query withArgumentsInArray:(NSArray*)arguments inDatabaseQueue:(FMDatabaseQueue*)databaseQueue{
    __block NSMutableArray *returnIt = [NSMutableArray array];
    [databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *resultSet = [db executeQuery:query withArgumentsInArray:arguments];
        NSArray *keys = [BROrm sortedKeysForResultSet:resultSet];
        
        while ([resultSet next]) {
            [returnIt addObject:[self dictionaryFromCurrentRowInResultSet:resultSet withKeys:keys]];
        }
        [resultSet close];
    }];
    if([returnIt count] == 0) return NULL;
    return [NSArray arrayWithArray:returnIt];
}

+ (BOOL)executeUpdate:(NSString*)query withArgumentsInArray:(NSArray*)arguments{
    if(!_defaultQueue) return false;
    return [self executeUpdate:query withArgumentsInArray:arguments inDatabaseQueue:_defaultQueue];
}

+ (BOOL)executeUpdate:(NSString*)query withArgumentsInArray:(NSArray*)arguments inDatabaseQueue:(FMDatabaseQueue*)databaseQueue{
    return [self executeUpdate:query withArgumentsInArray:arguments inDatabaseQueue:databaseQueue withLockBlock:^(FMDatabase *db){}];
}

+ (BOOL)executeUpdate:(NSString*)query withArgumentsInArray:(NSArray*)arguments inDatabaseQueue:(FMDatabaseQueue*)databaseQueue withLockBlock:(void (^)(FMDatabase *db))block{
    __block BOOL success = NO;
    [databaseQueue inDatabase:^(FMDatabase *db) {
        success = [db executeUpdate:query withArgumentsInArray:arguments];
        block(db);
    }];
    return success;
}

+ (BOOL)transactionSaveObjects:(NSArray*)objects inDatabaseQueue:(FMDatabaseQueue*)databaseQueue{
    __block BOOL success = NO;
    [databaseQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        
        BOOL success = true;
        
        for (BROrm *orm in objects) {
            success = success && [orm saveInTransaction:db];
        }
        
        if (!success) {
            *rollback = YES;
            return;
        }
    }];
    return success;
}

+ (void)setDefaultQueue:(FMDatabaseQueue*)databaseQueue{
    _defaultQueue = databaseQueue;
}

+ (FMDatabaseQueue*)defaultQueue{
    return _defaultQueue;
}

+ (NSString*)idColumn{
    return _idColumn;
}

#pragma mark -
#pragma mark reading

- (NSDictionary*)findOneAsDictionary:(NSString *)identifier{
    if(_isRawQuery){
        return [[self findManyAsDictionaries] firstObject];
    } else {
        _limit = @(1);
        return [[self findManyAsDictionaries] firstObject];
    }
}

- (BROrm *)findOne{
    return [self findOne:NULL];
}

- (BROrm *)findOne:(id)identifier{
    if(identifier){
        [_whereConditions removeAllObjects];
        [self whereIdIs:identifier];
    }
    
    NSDictionary *first_dict = [self findOneAsDictionary:identifier];
    if(!first_dict) return NULL;
    
    BROrm *first = [BROrm forTable:_tableName inDatabase:_databaseQueue];
    [first hydrate:first_dict];
    return first;
}

- (NSArray*)findMany{
    NSArray *many = [self findManyAsDictionaries];
    
    NSMutableArray *returnIt = [@[] mutableCopy];
    for (NSDictionary *one in many) {
        BROrm *current = [BROrm forTable:_tableName inDatabase:_databaseQueue];
        [current hydrate:one];
        [returnIt addObject:current];
    }
    return returnIt;
}

- (NSArray*)findManyAsDictionaries{
    return [self run];
}

- (int)count{
    if(_isRawQuery){
        return [[self findMany] count];
    } else {
        _columns = [NSMutableArray arrayWithArray:@[@"COUNT(*) as count"]];
        NSDictionary *result = [self findOneAsDictionary:NULL];
        return [[result objectForKey:@"count"] intValue];
    }
}

- (void)rawQuery:(NSString *)query withParameters:(NSArray*)parameters{
    _isRawQuery = YES;
    _rawQuery = query;
    _rawParameters = parameters;
}

- (void)select:(NSString*)column as:(NSString*)alias{
    [self addResultColumn:column as:alias];
}

- (void)selectExpression:(NSString*)expression as:(NSString*)alias{
    [self addResultColumn:expression as:alias];
}

- (void)whereType:(NSString*)type column:(NSString*)column value:(id)value{
    [self whereType:type column:column value:value trustValue:FALSE];
}

- (void)whereType:(NSString*)type column:(NSString*)column value:(id)value trustValue:(BOOL)trust{
    [_whereConditions addObject:@{@"column":column,@"type":type,@"value":value,@"trust_value":@(trust)}];
}
- (void)whereEquals:(NSString*)column value:(id)value{
    [self whereType:@"=" column:column value:value];
}
- (void)whereNotEquals:(NSString*)column value:(id)value{
    [self whereType:@"!=" column:column value:value];
}
- (void)whereIdIs:(id)value{
    [self whereType:@"=" column:_idColumn value:value];
}
- (void)whereLike:(NSString*)column value:(id)value{
    [self whereType:@"LIKE" column:column value:value];
}
- (void)whereNotLike:(NSString*)column value:(id)value{
    [self whereType:@"NOT LIKE" column:column value:value];
}

- (void)addJoinType:(NSString*)type onTable:(NSString*)table withConstraints:(NSArray*)constraints andAlias:(NSString*)alias{
    [_joins addObject:@{
                        @"type":type,
                        @"table":table,
                        @"constraints":constraints,
                        @"alias":alias}];
}
- (void)addJoin:(NSString*)table withConstraints:(NSArray*)constraints andAlias:(NSString*)alias{
    [self addJoinType:@"" onTable:table withConstraints:constraints andAlias:alias];
}

- (void)addOrderBy:(NSString*)column withOrdering:(NSString*)ordering{
    [_orders addObject:@{
                         @"column":column,
                         @"ordering":ordering}];
}

// TODO: add Having
// TODO: add Offset
// TODO: add Group by


#pragma mark writing


- (id)create{
    _isNew = YES;
    return self;
}

- (id)create:(NSDictionary*)data{
    _isNew = YES;
    if(data != NULL){
        [self hydrate:data];
        [self forceAllDirty];
    }
    return self;
}

- (void)hydrate:(NSDictionary*)data{
    _data = [data mutableCopy];
}



- (void)forceAllDirty{
    _dirtyFields = [[_data allKeys] mutableCopy];
}

- (void)generateSaveQueryWithBlock:(void (^)(NSString *query, NSArray *values))block{
    
    if([_dirtyFields count] == 0){
        block(NULL,NULL);
        return;
    }
    
    NSMutableDictionary *toSave = [NSMutableDictionary dictionary];
    for (NSString *key in _dirtyFields) {
        [toSave setObject:[_data objectForKey:key] forKey:key];
    }
    
    NSArray *values;
    NSString *query;
    if(_isNew){
        query = [self buildInsert:toSave];
        values = [toSave allValues];
    } else {
        query = [self buildUpdate:toSave];
        values = [[toSave allValues] arrayByAddingObject:[_data objectForKey:_idColumn]];
    }
    
    block(query,values);
}

- (BOOL)save{
    
    __block BOOL success = false;
    [self generateSaveQueryWithBlock:^(NSString *query,NSArray *values){
        if(query == NULL | values == NULL){
            success = true;
        } else {
            success = [BROrm executeUpdate:query withArgumentsInArray:values inDatabaseQueue:_databaseQueue withLockBlock:^(FMDatabase *db){
                if(_isNew){
                    [_data setObject:[NSNumber numberWithInteger:[db lastInsertRowId]] forKey:_idColumn];
                    _isNew = NO;
                }
            }];
        }
    }];
    
    if(success)
        _dirtyFields = [@[] mutableCopy];
    return success;
}

- (BOOL)saveInTransaction:(FMDatabase *)database{
    __block BOOL success = false;
    [self generateSaveQueryWithBlock:^(NSString *query,NSArray *values){
        if(query == NULL | values == NULL){
            success = true;
        } else {
            success = [database executeUpdate:query withArgumentsInArray:values];
            if(success){
                [_data setObject:[NSNumber numberWithInteger:[database lastInsertRowId]] forKey:_idColumn];
                _isNew = NO;
            }
        }
    }];
    if(success)
        _dirtyFields = [@[] mutableCopy];
    return success;
}


#pragma mark key subscripting
- (id)objectForKeyedSubscript:(id <NSCopying>)key{
    return [_data objectForKey:key];
}
- (void)setObject:(id)obj forKeyedSubscript:(id <NSCopying>)key{
    if([[_data objectForKey:key] isEqual:obj]) return;
    [_data setObject:obj forKey:key];
    if(![_dirtyFields containsObject:key])
        [_dirtyFields addObject:key];
}

#pragma mark -
#pragma mark private

#pragma mark read
- (void)addResultColumn:(NSString*)column as:(NSString*)alias{
    if(alias){
        [_columns addObject:[NSString stringWithFormat:@"%@ AS %@",column,alias]];
    } else {
        [_columns addObject:column];
    }
}

- (NSString*)buildSelect{
    if(_isRawQuery){
        _parameters = _rawParameters;
        return _rawQuery;
    }
    return [@[
              [self buildSelectStart],
               [self buildJoin],
               [self buildWhere],
//               $this->_build_group_by(),
//               $this->_build_having(),
               [self buildOrderBy],
               [self buildLimit],
//               $this->_build_offset(),
              ] componentsJoinedByString:@" "];
}

- (NSString*)buildSelectStart{
    NSString *columns;
    if([_columns count] == 0) columns = @"*";
    else columns = [_columns componentsJoinedByString:@", "];
    
    if (_distinct) {
        columns = [@"Distinct " stringByAppendingString:columns];
    }
    
    NSString *fragment = [NSString stringWithFormat:@"SELECT %@ FROM %@",columns,_tableName];
    
    if (_tableAlias) {
        fragment = [NSString stringWithFormat:@"%@ as %@",fragment,_tableAlias];
    }
    return fragment;
}

- (NSString*)buildJoin{
    NSMutableArray *joins = [NSMutableArray array];
    for (NSDictionary *join in _joins) {
        NSString *conditionstring = [self buildConditions:[join objectForKey:@"constraints"]];
        NSString *tablestring = [join objectForKey:@"table"];
        if([join objectForKey:@"alias"])
            [tablestring stringByAppendingString:[NSString stringWithFormat:@"AS %@",[join objectForKey:@"alias"]]];
        [joins addObject:[NSString stringWithFormat:@"%@ JOIN %@ ON (%@)",
                     [join objectForKey:@"type"],
                     [join objectForKey:@"table"],
                     conditionstring]];
    }
    return [joins componentsJoinedByString:@" "];
}

- (NSString*)buildLimit{
    if(!_limit) return @"";
    return [NSString stringWithFormat:@"LIMIT %i",[_limit intValue]];
}

- (NSString*)buildWhere{
    if([_whereConditions count] == 0) return @"";
    return [NSString stringWithFormat:@"WHERE %@",[self buildConditions:_whereConditions]];
}

- (NSString*)buildOrderBy{
    if([_orders count]==0) return @"";
    NSMutableArray *orders = [NSMutableArray array];
    for (NSDictionary *order in _orders) {
        [orders addObject:[NSString stringWithFormat:@"%@ %@",
                           [order objectForKey:@"column"],
                           [order objectForKey:@"ordering"]]];
    }
    return [@"ORDER BY " stringByAppendingString:[orders componentsJoinedByString:@", "]];
}

- (NSString*)buildConditions:(NSArray*)conditions{
    NSMutableArray *conditionsarray = [NSMutableArray array];
    NSMutableArray *m_parameters = [_parameters mutableCopy];
    if(!m_parameters) m_parameters = [@[] mutableCopy];
    for (NSDictionary *condition in conditions) {
        if([[condition objectForKey:@"trust_value"] boolValue]){
            [conditionsarray addObject:[NSString stringWithFormat:@"%@ %@ %@",[condition objectForKey:@"column"],[condition objectForKey:@"type"],[condition objectForKey:@"value"]]];
        } else {
            [conditionsarray addObject:[NSString stringWithFormat:@"%@ %@ ?",[condition objectForKey:@"column"],[condition objectForKey:@"type"]]];
            [m_parameters addObject:[condition objectForKey:@"value"]];
        }
    }
    _parameters = m_parameters;
    if([conditionsarray count] == 0) return @"";
    return [conditionsarray componentsJoinedByString:@" AND "];
}

- (NSArray*)run{
    NSString *query = [self buildSelect];
    NSLog(@"query: %@ with: %@",query,_parameters);
    return [BROrm executeQuery:query withArgumentsInArray:_parameters inDatabaseQueue:_databaseQueue];
}

+ (NSArray*)sortedKeysForResultSet:(FMResultSet*)resultSet{
    NSMutableArray *returnIt = [NSMutableArray array];
    for(int i = 0; i<[resultSet columnCount]; i++)
        [returnIt addObject:[resultSet columnNameForIndex:i]];
    return [NSArray arrayWithArray:returnIt];
}

+ (NSDictionary*)dictionaryFromCurrentRowInResultSet:(FMResultSet*)resultSet withKeys:(NSArray*)keys{
    if(![resultSet hasAnotherRow]) return NULL;
    
    NSMutableDictionary *returnIt = [NSMutableDictionary dictionary];
    
    for (NSString *key in keys) {
        [returnIt setObject:[resultSet objectForColumnName:key] forKey:key];
    }
    
    return [NSDictionary dictionaryWithDictionary:returnIt];
}

#pragma mark write


- (NSString*)buildUpdate:(NSDictionary*)data{
    NSString *query = [NSString stringWithFormat:@"UPDATE %@ SET ",_tableName];
    
    NSMutableArray *fields = [NSMutableArray array];
    for (NSString *key in data) {
        [fields addObject:[NSString stringWithFormat:@"%@ = ?",key]];
    }
    query = [query stringByAppendingString:[fields componentsJoinedByString:@", "]];
    query = [query stringByAppendingString:[NSString stringWithFormat:@" WHERE %@ = ?",_idColumn]];
    return query;
}
- (NSString*)buildInsert:(NSDictionary*)data{
    NSString *query = [NSString stringWithFormat:@"INSERT INTO %@ ",_tableName];
    
    NSMutableArray *fields = [NSMutableArray array];
    NSMutableArray *placeholders = [NSMutableArray array];
    for (NSString *key in data) {
        [fields addObject:key];
        [placeholders addObject:@"?"];
    }
    query = [query stringByAppendingString:[NSString stringWithFormat:@"(%@)",[fields componentsJoinedByString:@", "]]];
    query = [query stringByAppendingString:[NSString stringWithFormat:@" VALUES (%@)",[placeholders componentsJoinedByString:@", "]]];
    return query;
}

@end
