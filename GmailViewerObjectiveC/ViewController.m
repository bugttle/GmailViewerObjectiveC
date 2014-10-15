//
//  ViewController.m
//  GmailViewerObjectiveC
//
//  Created by Ryo Tsuruda on 10/14/14.
//  Copyright (c) 2014 UQ Times. All rights reserved.
//

#import "ViewController.h"

#import "GTLGmail.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "GTLBase64.h"

#error @"Please input your account."
// クライアント ID
NSString *const kClientID = @"";
// クライアント シークレット
NSString *const kClientSecret = @"";
// キーチェンに保存する用のアイテム名
NSString *const kKeychainItemName = @"GmailViewerObjectiveC";

@interface ViewController ()
@property (nonatomic, readonly) GTLServiceGmail *gmailService;
@property (nonatomic, retain) NSMutableArray *messages;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (![self isSignedIn]) {
        [self signIn];
    } else {
        [self fetchUnreadMessagesList];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - UITableViewDataSource methods

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    GTLGmailMessage *message = [self.messages objectAtIndex:indexPath.row];
    GTLGmailMessagePart *payload = message.payload;
    for (GTLGmailMessagePartHeader *header in payload.headers) {
        if ([header.name isEqualToString:@"Subject"]) {
            cell.textLabel.text = [NSString stringWithFormat:@"%d:%@", (indexPath.row+1), header.value];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.messages.count) {
        GTLGmailMessage *message = self.messages[indexPath.row];
        [self modifyMessages:@[message.identifier] withLabelsToAdd:nil withLabelsToRemove:@[@"UNREAD"]];
    }
}

#pragma mark - GTL methods

/* GmailServiceのシングルトン */
- (GTLServiceGmail *)gmailService {
    static GTLServiceGmail *service = nil;
    if (!service) {
        service = [[GTLServiceGmail alloc] init];
        //service.shouldFetchNextPages = YES; // 次のリクエストも自動発行
        service.retryEnabled = YES;
    }
    return service;
}

/* Keychainに保存されている認証情報を検索 */
- (GTMOAuth2Authentication *)retrieveAuthorization {
    NSError *error = nil;
    GTMOAuth2Authentication *auth = [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:kKeychainItemName
                                                                                          clientID:kClientID
                                                                                      clientSecret:kClientSecret
                                                                                             error:&error];
    return (error) ? nil : auth;
}

/* サインインしているかの判定 */
- (BOOL)isSignedIn {
    if (!self.gmailService.authorizer) {
        self.gmailService.authorizer = [self retrieveAuthorization];
    }
    return self.gmailService.authorizer.canAuthorize;
}

/* サインイン */
- (void)signIn {
    GTMOAuth2ViewControllerTouch *vc = [[GTMOAuth2ViewControllerTouch alloc] initWithScope:kGTLAuthScopeGmailModify
                                                                                  clientID:kClientID
                                                                              clientSecret:kClientSecret
                                                                          keychainItemName:kKeychainItemName
                                                                         completionHandler:^(GTMOAuth2ViewControllerTouch *viewController, GTMOAuth2Authentication *auth, NSError *error) {
                                                                             if (error) {
                                                                                 NSLog(@"failed to auth: error=%@", [error  description]);
                                                                             } else {
                                                                                 self.gmailService.authorizer = auth;
                                                                             }
                                                                             [viewController dismissViewControllerAnimated:YES completion:nil];
                                                                         }];
    [self presentViewController:vc animated:YES completion:nil];
}

/* サインアウト */
- (void)signOut {
    [GTMOAuth2ViewControllerTouch removeAuthFromKeychainForName:kKeychainItemName];
    if (self.gmailService.authorizer) {
        [GTMOAuth2ViewControllerTouch revokeTokenForGoogleAuthentication:self.gmailService.authorizer];
        self.gmailService.authorizer = nil;
    }
}

#pragma mark - API request methods

/* 未読のメッセージリストを取得 */
- (void)fetchUnreadMessagesList {
    [self fetchMessagesList:@"is:unread"];
}

/* メッセージリストの取得 */
- (void)fetchMessagesList:(NSString *)q {
    GTLQueryGmail *query = [GTLQueryGmail queryForUsersMessagesList];
    query.q = q;
    [self.gmailService executeQuery:query
                  completionHandler:^(GTLServiceTicket *ticket, id object, NSError *error) {
                      if (error) {
                          NSLog(@"failed to get messages list: error=%@", [error description]);
                      } else {
                          GTLGmailListMessagesResponse *response = object;
                          NSMutableArray *messageIdentifiers = [NSMutableArray array];
                          for (GTLGmailMessage *message in response.messages) {
                              [messageIdentifiers addObject:message.identifier];
                          }
                          [self fetchMessagesGet:messageIdentifiers];
                      }
                  }];
}

/* メッセージ本文の取得 */
- (void)fetchMessagesGet:(NSArray *)identifiers {
    GTLBatchQuery *batch = [GTLBatchQuery batchQuery];
    for (NSString *identifier in identifiers) {
        GTLQueryGmail *query = [GTLQueryGmail queryForUsersMessagesGet];
        query.identifier = identifier;
        [batch addQuery:query];
    }
    [self.gmailService executeQuery:batch
                  completionHandler:^(GTLServiceTicket *ticket, id object, NSError *error) {
                      if (error) {
                          NSLog(@"failed to get messages: error=%@", [error description]);
                      } else {
                          self.messages = [NSMutableArray array];
                          GTLBatchResult *batchResult = object;
                          NSDictionary *successes = batchResult.successes;
                          for (NSString *requestID in successes) {
                              GTLQuery *query = [ticket queryForRequestID:requestID];
                              GTLGmailMessage *message = [successes objectForKey:requestID];
                              NSLog(@"Query returned object: query=%@, object=%@", query, message);
                              [self.messages addObject:message];
                              [self.tableView reloadData];
                          }
                          NSDictionary *failures = batchResult.failures;
                          for (NSString *requestID in failures) {
                              GTLQuery *query = [ticket queryForRequestID:requestID];
                              GTLErrorObject *errorObject = [failures objectForKey:requestID];
                              NSLog(@"Query returned error object: query=%@, object=%@", query, errorObject);
                          }
                      }
                  }];
}

/* メッセージの更新 */
- (void)modifyMessages:(NSArray *)identifiers withLabelsToAdd:(NSArray *)labelsToAdd withLabelsToRemove:(NSArray *)labelsToRemove {
    GTLBatchQuery *batch = [GTLBatchQuery batchQuery];
    for (NSString *identifier in identifiers) {
        GTLQueryGmail *query = [GTLQueryGmail queryForUsersMessagesModify];
        query.identifier = identifier;
        query.addLabelIds = labelsToAdd;
        query.removeLabelIds = labelsToRemove;
        [batch addQuery:query];
    }
    [self.gmailService executeQuery:batch
                  completionHandler:^(GTLServiceTicket *ticket, id object, NSError *error) {
                      if (error) {
                          NSLog(@"failed to modify messages: error=%@", [error description]);
                      } else {
                          GTLBatchResult *batchResult = object;
                          NSDictionary *successes = batchResult.successes;
                          for (NSString *requestID in successes) {
                              GTLQuery *query = [ticket queryForRequestID:requestID];
                              GTLGmailMessage *message = [successes objectForKey:requestID];
                              NSLog(@"Query returned object: query=%@, object=%@", query, message);
                          }
                          NSDictionary *failures = batchResult.failures;
                          for (NSString *requestID in failures) {
                              GTLQuery *query = [ticket queryForRequestID:requestID];
                              GTLErrorObject *errorObject = [failures objectForKey:requestID];
                              NSLog(@"Query returned error object: query=%@, object=%@", query, errorObject);
                          }
                          // メッセージリストの再取得
                          [self fetchUnreadMessagesList];
                      }
                  }];
}

@end
