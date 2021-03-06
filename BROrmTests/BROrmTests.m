//
//  BROrmTests.m
//  BROrmTests
//
//  Created by Cornelius Horstmann on 15.06.13.
//  Copyright (c) 2013 brototyp.de. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "BROrm.h"
#import "FMDatabase.h"
#import "FMDatabaseQueue.h"

@interface BROrmTests : XCTestCase{
    FMDatabaseQueue *_databaseQueue;
}

@end

@implementation BROrmTests

- (void)setUp
{
    [super setUp];
    _databaseQueue = [FMDatabaseQueue databaseQueueWithPath:[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"test.sqlite"]];
    [_databaseQueue inDatabase:^(FMDatabase *db) {
        [db open];
        db.logsErrors = YES;
    }];
    
    [BROrm setDefaultQueue:_databaseQueue];
    
    [BROrm executeUpdate:@"CREATE TABLE IF NOT EXISTS testtable (identifier INTEGER PRIMARY KEY AUTOINCREMENT, string TEXT, int INTEGER);" withArgumentsInArray:NULL];
    [BROrm executeUpdate:@"INSERT INTO testtable (string, int) VALUES (?,?)" withArgumentsInArray:@[@"string",@(1)]];
    
    [BROrm executeUpdate:@"CREATE TABLE IF NOT EXISTS jointable (identifier INTEGER PRIMARY KEY AUTOINCREMENT, string TEXT, foreign_key INTEGER);" withArgumentsInArray:NULL];
    [BROrm executeUpdate:@"INSERT INTO jointable (string, foreign_key) VALUES (?,?)" withArgumentsInArray:@[@"joinstring",@(1)]];

}

- (void)tearDown
{
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"test.sqlite"] error:NULL];
    
    [super tearDown];
}

- (void)testForTableInDatabase
{
    BROrm *orm = [BROrm forTable:@"testtable"];
    XCTAssertNotNil(orm, @"BROrm Objekt kann nicht erstellt werden.");
    XCTAssertEqualObjects(orm.databaseQueue, _databaseQueue, @"FMDatabaseQueue wird nicht korrekt übernommen.");
}

- (void)testForRawQueryFindMany{
    BROrm *orm = [BROrm forTable:@"testtable"];
    [orm rawQuery:@"SELECT * FROM testtable" withParameters:NULL];
    NSArray *result = [orm findMany];
    XCTAssertTrue([result count] == 1, @"");
}

- (void)testForRawQueryFindOne{
    BROrm *orm = [BROrm forTable:@"testtable"];
    [orm rawQuery:@"SELECT * FROM testtable" withParameters:NULL];
    BROrm *result = [orm findOne:NULL];
    XCTAssertNotNil(result, @"");
}
- (void)testForRawQueryCount{
    BROrm *orm = [BROrm forTable:@"testtable"];
    [orm rawQuery:@"SELECT * FROM testtable" withParameters:NULL];
    int result = [orm count];
    XCTAssertTrue(result == 1, @"");
}

- (void)testForSimpleSelect{
    BROrm *orm = [BROrm forTable:@"testtable"];
    [orm select:@"identifier" as:@"id"];
    BROrm *result = [orm findOne:NULL];
    XCTAssertNotNil(result, @"");
}

- (void)testForSimpleSelectCount{
    BROrm *orm = [BROrm forTable:@"testtable"];
    [orm select:@"identifier" as:@"id"];
    int result = [orm count];
    XCTAssertTrue(result == 1, @"");
}

- (void)testForSimpleWhereEquals{
    BROrm *orm = [BROrm forTable:@"testtable"];
    [orm select:@"identifier" as:@"id"];
    [orm whereEquals:@"id" value:@(1)];
    [orm whereEquals:@"string" value:@"string"];
    BROrm *result = [orm findOne:NULL];
    XCTAssertNotNil(result, @"");
    
    orm = [BROrm forTable:@"testtable"];
    [orm select:@"identifier" as:@"id"];
    [orm whereEquals:@"id" value:@(5)];
    result = [orm findOne:NULL];
    XCTAssertNil(result, @"");
}

- (void)testForSimpleJoin{
    BROrm *orm = [BROrm forTable:@"testtable"];
    [orm select:@"testtable.identifier" as:@"id"];
    [orm select:@"jointable.string" as:@"joinstring"];
    [orm addJoin:@"jointable" withConstraints:@[@{@"type":@"=",@"column":@"testtable.identifier",@"value":@"jointable.foreign_key",
                                                  @"trust_value":@(1)}] andAlias:@"jointable"];
    BROrm *result = [orm findOne:NULL];
    XCTAssertNotNil(result[@"joinstring"], @"");
}

// TODO: write this test
//- (void)testForSorting{
//    XCTAssertNotNil(NULL, @"Fehlender Test");
//}

- (void)testForCreateAndSave{
    BROrm *orm = [BROrm forTable:@"testtable"];
    [orm create:@{
                  @"string":@"foo",
                  @"int":@(1)}];
    [orm save];
    
    
    BROrm *orm2 = [BROrm forTable:@"testtable"];
    [orm2 select:@"*" as:NULL];
    [orm2 whereEquals:@"identifier" value:orm[@"identifier"]];
    BROrm *result = [orm2 findOne:NULL];
    XCTAssertEqualObjects(orm[@"string"], @"foo", @"Insert klappt nicht");
    
    [orm setObject:@"bar" forKeyedSubscript:@"string"];
    [orm save];
    
    result = [orm2 findOne:NULL];
    XCTAssertEqualObjects(result[@"string"], @"bar", @"Update klappt nicht");
}

@end
