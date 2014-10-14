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
@property (readonly) GTLServiceGmail *gmailService;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewDidAppear:(BOOL)animated
{
    if (![self isSignedIn]) {
        [self signIn];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

/* GmailServiceのシングルトン */
- (GTLServiceGmail *)gmailService {
    static GTLServiceGmail *service = nil;
    if (!service) {
        service = [[GTLServiceGmail alloc] init];
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
    GTMOAuth2ViewControllerTouch *vc = [[GTMOAuth2ViewControllerTouch alloc] initWithScope:kGTLAuthScopeGmailReadonly
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

@end
