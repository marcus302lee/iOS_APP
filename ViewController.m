//
//  ViewController.m
//  WebViewTest
//
//  Created by Seungil Shin on 2021/12/07.
//
#import "SimpleLoginViewController.h"
#import "Preferences.h"
#import "AppDelegate.h"
#import "HttpPostMultipart.h"
#import "NSString+AESCrypt.h"
#import <WebKit/WebKit.h>

#import "ViewController.h"
#import "Utils.h"
#import "PushNotificationManager.h"

#import <Photos/Photos.h>
#import "ToastView.h"

#define isNull(value) value == nil || [value isKindOfClass:[NSNull class]]

@interface ViewController ()
{
    WKUserScript * cookieScript;
}

@property (retain, nonatomic) WKWebView *webkitview;
@property (retain, nonatomic) WKWebView *popupWebView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
//    webview.navigationDelegate = self;
//    webview.UIDelegate = self;

    
    WKUserContentController *content_cont = [[WKUserContentController alloc] init];
    WKWebViewConfiguration *wconf = [[WKWebViewConfiguration alloc] init];
    wconf.userContentController = content_cont;
    [self addFunctions:content_cont];

    [webview removeFromSuperview];

    // xib 상의 웹뷰를 브릿지 함수 처리가 가능한 웹뷰로 대치
    WKWebView *awebview = [[WKWebView alloc] initWithFrame:webview.frame configuration:wconf];
    [self.view addSubview:awebview];
    awebview.UIDelegate = self;
    awebview.navigationDelegate = self;
    awebview.contentMode = webview.contentMode;
    awebview.autoresizingMask = webview.autoresizingMask;
    
#ifdef DEBUG
    if (@available(iOS 16.4, *)) {
        [awebview setInspectable:TRUE];
    }
#endif
    
    webview = awebview;
    if(_loadURL) [self loadURLString:_loadURL];
    btn_Back = [UIButton buttonWithType:UIButtonTypeCustom];
    [btn_Back setFrame:CGRectMake((awebview.bounds.size.width - 50), ([self getStatusBarHeight] + 5), 40, 40)];
    [btn_Back setImage:[UIImage imageNamed:@"btn_close"] forState:UIControlStateNormal];
    [btn_Back addTarget:self action:@selector(webviewBack:) forControlEvents:UIControlEventTouchUpInside];
    btn_Back.hidden = YES;
    [webview addSubview:btn_Back];

    UIView *statusBarView = nil;
    if (@available(iOS 13.0, *))
    {
        CGRect rect = [UIApplication sharedApplication].keyWindow.windowScene.statusBarManager.statusBarFrame;
        statusBarView = [[UIView alloc] initWithFrame:rect];
        [self.view addSubview:statusBarView];
    }
    else
    {
        statusBarView = [[UIApplication sharedApplication] valueForKey:@"statusBar"];
    }
    
    if (statusBarView)
    {
        BOOL isDarkMode = ([self traitCollection].userInterfaceStyle == UIUserInterfaceStyleDark);
        [statusBarView setBackgroundColor:(isDarkMode ? [UIColor blackColor] : [UIColor whiteColor])];
    }
    [AFHTTPRequestSerializer serializer];
    
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    Utils *utils = [Utils sharedInstance];
    //[utils checkJailBreak];
    
    AFNetworkReachabilityStatus networkStatus = [utils getCurNetworkStatus];
    if (networkStatus == AFNetworkReachabilityStatusNotReachable)
    {
        [utils showNoConnectivityAlert];
    }
}

- (PHAuthorizationStatus)checkPhotoPermission {
    BOOL bOK = TRUE;
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (@available(iOS 14, *)) {
        if( status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited )
        {
            bOK = FALSE;
        }
    }
    else
    {
        if( status != PHAuthorizationStatusAuthorized  )
        {
            bOK = FALSE;
        }
    }
        
    if ( !bOK )
    {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status != PHAuthorizationStatusAuthorized)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *accessDescription = @"U+웹팩스 다운로드";
                    UIAlertController * alertController = [UIAlertController alertControllerWithTitle:accessDescription message:@"U+웹팩스에서 다운로드 기능을 사용하기 위헤서는 사진 접근 권한이 필요합니다." preferredStyle:UIAlertControllerStyleAlert];
                    
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    
                    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                    }];
                    
                    [alertController addAction:settingsAction];
                    [self presentViewController:alertController animated:YES completion:^{}];
                });
                
               
            }
        }];
    }
    
    status = [PHPhotoLibrary authorizationStatus];
    return status;
}

- (void)saveToAlbum:(UIImage *)image {
    NSString *albumName = @"U+웹팩스";

    void (^saveBlock)(PHAssetCollection *assetCollection) = ^void(PHAssetCollection *assetCollection) {
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetChangeRequest *assetChangeRequest = [PHAssetChangeRequest creationRequestForAssetFromImage:image];

            PHAssetCollectionChangeRequest *assetCollectionChangeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:assetCollection];
            [assetCollectionChangeRequest addAssets:@[[assetChangeRequest placeholderForCreatedAsset]]];

        } completionHandler:^(BOOL success, NSError *error) {
            if (!success) {
                NSLog(@"Error creating asset: %@", error);
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.view hideToastActivity];
                    
                    [self.view makeToast:@"다운로드에 실패하였습니다.\n잠시 후 다시 시도해 주세요."];
                });
            }
            else
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.view hideToastActivity];
                    
                    [self.view makeToast:@"다운로드가 완료되었습니다.\n'사진 > 앨범 > U+웹팩스'에서 확인 가능합니다."];
                });
            }
            
        }];
    };

    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"localizedTitle = %@", albumName];
    PHFetchResult *fetchResult = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:fetchOptions];
    if (fetchResult.count > 0) {
        saveBlock(fetchResult.firstObject);
    } else {
        __block PHObjectPlaceholder *albumPlaceholder;
        
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCollectionChangeRequest *changeRequest = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:albumName];
            albumPlaceholder = changeRequest.placeholderForCreatedAssetCollection;

        } completionHandler:^(BOOL success, NSError *error) {
            if (success) {
                PHFetchResult *fetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[albumPlaceholder.localIdentifier] options:nil];
                if (fetchResult.count > 0) {
                    saveBlock(fetchResult.firstObject);
                }
            } else {
                NSLog(@"Error creating album: %@", error);
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.view hideToastActivity];
                    
                    [self.view makeToast:@"다운로드에 실패하였습니다.\n잠시 후 다시 시도해 주세요."];
                });
            }
        }];
    }
}

- (NSString *)deviceModelName {
    NSString *modelName = NSProcessInfo.processInfo.environment[@"SIMULATOR_DEVICE_NAME"];
    if (modelName.length > 0) {
        return modelName;
    }

    UIDevice *device = [UIDevice currentDevice];
    NSString *selName = [NSString stringWithFormat:@"_%@ForKey:", @"deviceInfo"];
    SEL selector = NSSelectorFromString(selName);
    
    if ([device respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        modelName = [device performSelector:selector withObject:@"marketing-name"];
#pragma clang diagnostic pop
    }
    
    return modelName;
}

-(NSString*)getVersion {
    NSDictionary *infoDictionary = [[NSBundle mainBundle]infoDictionary];
    return infoDictionary[@"CFBundleShortVersionString"];
}

-(void)downloadImage:(NSString *)url_str imageFile:(NSString*)imageFile
{
    PHAuthorizationStatus status = [self checkPhotoPermission];
    BOOL bOK = status == PHAuthorizationStatusAuthorized;
    
    if (@available(iOS 14, *)) {
        if( !bOK && status == PHAuthorizationStatusLimited )
        {
            bOK = TRUE;
        }
    }
    
    if( bOK )
    {
        [self.view makeToastActivity:CSToastPositionCenter];
        
        NSArray<NSHTTPCookie *> *cookies = NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies;
        WKHTTPCookieStore *cookie_store = webview.configuration.websiteDataStore.httpCookieStore;
        for(int i=0;i<cookies.count;i++) {
            NSHTTPCookie *cookie = cookies[i];
            [cookie_store setCookie:cookie completionHandler:nil];
        }
        
        NSURL *url = [NSURL URLWithString:url_str];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setHTTPMethod:@"POST"];
        
        id cookie_dict = [NSHTTPCookie requestHeaderFieldsWithCookies: cookies];// NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies];=
        NSMutableDictionary *headers = (NSMutableDictionary *)request.allHTTPHeaderFields;
        if(headers == nil) {
            headers = [NSMutableDictionary dictionary];
        }
        
        NSArray *keys = [cookie_dict allKeys];
        for(NSString *key in keys) { // keys must be only 1.
            NSString *cookie_str = cookie_dict[key];
            //cookie_str = [NSString stringWithFormat:@"%@;domain=%@",cookie_str, url.host];
            headers[key] =  cookie_str;
        }
        
        NSString *stringData = [NSString stringWithFormat:@"imageFile=%@", imageFile];
        NSData *body = [stringData dataUsingEncoding:NSUTF8StringEncoding];
        
        [request setHTTPBody:body];
        [request setAllHTTPHeaderFields:headers];
        
        NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                         completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if( data != nil && error == nil )
            {
                UIImage* img = [UIImage imageWithData:data];
                [self saveToAlbum:img];
            }
            else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.view hideToastActivity];
                    
                    [self.view makeToast:@"다운로드에 실패하였습니다.\n잠시 후 다시 시도해 주세요."];
                });
            }
        }];
        [dataTask resume];
    }
    
}

- (void)loadURLString:(NSString *)url_str //para:(NSDictionary *)para_dict
{
    // 세션 유지를 위해 저장된 쿠키들을 웹뷰 쿠키스토어에 저장한다.
    NSArray<NSHTTPCookie *> *cookies = NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies;
    WKHTTPCookieStore *cookie_store = webview.configuration.websiteDataStore.httpCookieStore;
    for(int i=0;i<cookies.count;i++) {
        NSHTTPCookie *cookie = cookies[i];
        [cookie_store setCookie:cookie completionHandler:nil];

    }
    
    NSURL *url = [NSURL URLWithString:url_str];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    // request header 에도 쿠키를 저장한다.
    // 관제현황 이상형황  정상
    id cookie_dict = [NSHTTPCookie requestHeaderFieldsWithCookies: cookies];// NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies];=
    NSMutableDictionary *headers = (NSMutableDictionary *)request.allHTTPHeaderFields;
    if(headers == nil) {
        headers = [NSMutableDictionary dictionary];
    }
    
    NSString *js_cookie_str = @"";
    NSArray *keys = [cookie_dict allKeys];
    for(NSString *key in keys) { // keys must be only 1.
        NSString *cookie_str = cookie_dict[key];
        //cookie_str = [NSString stringWithFormat:@"%@;domain=%@",cookie_str, url.host];
        headers[key] =  cookie_str;
        js_cookie_str = cookie_str;
    }
    if(self.isLoggined) {
        NSString *logins = [Preferences sharedPreferences].userID;
        NSString *aesvec = [NSString stringWithFormat:@"%@_AESVector", @"WebFaxIOS"];
        NSString *aeskey = [NSString stringWithFormat:@"%@_AESEncKey", @"WebFaxIOS"];
        logins = [logins AES128DecryptWithKey:aeskey vector:aesvec];
//        if(logins.length > 0) js_cookie_str = [NSString stringWithFormat:@"%@;applogin=%@", js_cookie_str, logins]; // 로그인되었을때 받은 로그인정보(아이
        if(logins.length > 0) js_cookie_str = [NSString stringWithFormat:@"applogin=%@", logins]; // 로그인되었을때 받은 로그인정보(아이
    }
    //headers[@"Content-Type"] = @"application/x-www-form-urlencoded"; //@"text/plain;charset=UTF-8";
    //request.allHTTPHeaderFields = headers;
    
    // Set Request Header: 로그인이 진행되지 않은 문제가 있음
    [request setValue:@"iOSmobile" forHTTPHeaderField:@"UPLUS-FAX-Platform"];
    [request setValue:[[[UIDevice currentDevice] identifierForVendor] UUIDString] forHTTPHeaderField:@"UPLUS-FAX-DeviceId"];
    [request setValue:[self deviceModelName] forHTTPHeaderField:@"UPLUS-FAX-ModelNm"];
    [request setValue:[self getVersion] forHTTPHeaderField:@"UPLUS-FAX-AppVersion"];
    
    // iOS 12 에서는 HTML 내 ajax 호출시 세션을 잃어버리는 문제가 있음.
    
    NSString* fcmToken = [[PushNotificationManager sharedInstance] getFcmToken];
    if( fcmToken == NULL || [fcmToken isEqual:[NSNull null]] || fcmToken.length <= 0 )
    {
        [[FIRMessaging messaging] tokenWithCompletion:^(NSString *token, NSError *error) {
            
            if (error == nil) {
 
                NSString* js_cookie_str2 = [NSString stringWithFormat:@"document.cookie = 'fcmToken=%@'",token];
                
                self->cookieScript = [[WKUserScript alloc]
                    initWithSource: js_cookie_str2 injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];

                WKWebViewConfiguration *wconf = self->webview.configuration;
                WKUserContentController *content_cont = wconf.userContentController;
                [content_cont addUserScript:self->cookieScript];
            }
            
            NSString* cookie_str = [NSString stringWithFormat:@"document.cookie = '%@'", js_cookie_str];
            self->cookieScript = [[WKUserScript alloc]
                initWithSource:cookie_str injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];


            WKWebViewConfiguration *wconf = self->webview.configuration;
            WKUserContentController *content_cont = wconf.userContentController;
            [content_cont addUserScript:self->cookieScript];

            [self->webview loadRequest:request];
        }];
    }
    else
    {
        NSString* js_cookie_str2 = [NSString stringWithFormat:@"document.cookie = 'fcmToken=%@'",fcmToken];
        cookieScript = [[WKUserScript alloc]
            initWithSource: js_cookie_str2 injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];

        WKWebViewConfiguration *wconf = webview.configuration;
        WKUserContentController *content_cont = wconf.userContentController;
        [content_cont addUserScript:cookieScript];
        
        js_cookie_str = [NSString stringWithFormat:@"document.cookie = '%@'",js_cookie_str];
        cookieScript = [[WKUserScript alloc]
            initWithSource: js_cookie_str injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];

        [content_cont addUserScript:cookieScript];

        
        [webview loadRequest:request];
    }
}


- (void)addFunctions:(WKUserContentController *)content_cont
{
    [content_cont addScriptMessageHandler:self name:@"openLogin"]; // window.tracking.backPress();
    [content_cont addScriptMessageHandler:self name:@"getPhoneImage"]; // window.tracking.backPress();
    [content_cont addScriptMessageHandler:self name:@"openLoginSetup"]; // window.tracking.backPress();
    [content_cont addScriptMessageHandler:self name:@"getCameraImage"]; // window.tracking.backPress();
    [content_cont addScriptMessageHandler:self name:@"storeUserInfo"]; // window.tracking.backPress();
    
    [content_cont addScriptMessageHandler:self name:@"getGcmId"];
}


// 셀프 인증 서버 연결시 인증서 확인 과정을 회피하기 위해 필요한 코드
- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential  * credential))completionHandler {

    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    completionHandler(NSURLSessionAuthChallengeUseCredential,
    [NSURLCredential credentialForTrust:serverTrust]);
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(null_unspecified WKNavigation *)navigation
{
    NSLog(@"didReceiveServerRedirectForProvisionalNavigation");
}


#pragma mark - WKWebView delegate methods

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * __nullable credential))completionHandler{
    NSLog(@"didReceiveChallenge");
//    if([challenge.protectionSpace.host isEqualToString:@"api.lz517.me"] /*check if this is host you trust: */ ){
    completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
//    }
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"확인"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
                                                          completionHandler();
                                                      }]];
    [self presentViewController:alertController animated:YES completion:^{}];
}

- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)navigationAction didBecomeDownload:(WKDownload *)download API_AVAILABLE(ios(14.5)){
    download.delegate = self;
}

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL * _Nullable))completionHandler API_AVAILABLE(ios(14.5)){
    NSURL *temporaryDirectory = [NSFileManager.defaultManager temporaryDirectory];
    NSURL *url = [temporaryDirectory URLByAppendingPathComponent:suggestedFilename];
    completionHandler(url);

}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    if (url != nil && ![url.scheme isEqual:@"http"] && ![url.scheme isEqual:@"https"]) {
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            // 카드사 앱, tel:, sms:, itms-apps: 등 외부 앱 실행
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
        // canOpenURL 결과와 무관하게 WebView 로드는 항상 취소
        // (canOpenURL 실패 시에도 WebView가 알 수 없는 스킴을 처리하지 않도록 방지)
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    if([url.path isEqualToString:@"/tips/html/tip/event.html"] || [url.path isEqualToString:@"/tips/html/tip/webfax-info.html"] || [url.path isEqualToString:@"/tips/html/tip/webfax-info-sub.html"] ) {
        btn_Back.hidden = NO;
    }
    else if([url.absoluteString rangeOfString:Preferences.sharedPreferences.faxHost].length < 1) {
        if(![_popupWebView superview]) btn_Back.hidden = NO;
    }
    else {
        btn_Back.hidden = YES;
    }
    
    if( [url.path hasSuffix:@"/fax/download/images"] )
    {
        decisionHandler(WKNavigationActionPolicyCancel);
        
        [webView evaluateJavaScript:@"document.getElementById('imageFile').value" completionHandler:^(id result, NSError *error) {
           if( error == nil && result != nil )
           {
               NSString* fileUrl = [NSString stringWithFormat:@"%@", result];
               
               NSDictionary *infoDic = [[NSBundle mainBundle] infoDictionary];
               NSString *server_url = [infoDic objectForKey:@"ServerURL"];
               NSString* urlX = [NSString stringWithFormat:@"https://%@%@", server_url, url.path];
               
               [self downloadImage:urlX imageFile:fileUrl];
           }
        }];
        
        return;
    }
    
    WKHTTPCookieStore *cookie_store = webView.configuration.websiteDataStore.httpCookieStore;
    [cookie_store getAllCookies:^(NSArray<NSHTTPCookie *> * _Nonnull cookies) {
        NSInteger i, icnt = cookies.count;
        for(i=0;i<icnt;i++) {
            NSHTTPCookie *cookie = cookies[i];
            [NSHTTPCookieStorage.sharedHTTPCookieStorage setCookie:cookie];
        }
    }];
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (nullable WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    _popupWebView = [[WKWebView alloc] initWithFrame:webview.frame configuration:configuration];
    _popupWebView.navigationDelegate = self;
    _popupWebView.UIDelegate = self;
    [self.view addSubview:_popupWebView];    // 눈에 보여지도록
    
    UIButton *btnClose = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnClose setFrame:CGRectMake((_popupWebView.bounds.size.width - 50), ([self getStatusBarHeight] + 5), 40, 40)];
    [btnClose setImage:[UIImage imageNamed:@"btn_close"] forState:UIControlStateNormal];
    [btnClose addTarget:self action:@selector(popupClose:) forControlEvents:UIControlEventTouchUpInside];
    [_popupWebView addSubview:btnClose];

    return _popupWebView;
}

- (void)webViewDidClose:(WKWebView *)webView_
{
    if (webView_ == _popupWebView)
    {
        [self popupClose:nil];
    }
}

#define IS_IPHONE                                       (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
#define SCREEN_WIDTH                                    ([UIScreen mainScreen].bounds.size.width)
#define SCREEN_HEIGHT                                   ([UIScreen mainScreen].bounds.size.height)
#define SCREEN_MAX_LENGTH                               (MAX(SCREEN_WIDTH, SCREEN_HEIGHT))

- (CGFloat)getStatusBarHeight
{
    CGFloat height = 0.0;
    
    if (@available(iOS 13.0, *))
    {
        height = [UIApplication sharedApplication].keyWindow.windowScene.statusBarManager.statusBarFrame.size.height;
    }
    else
    {
        height = ((IS_IPHONE && SCREEN_MAX_LENGTH >= 812.0) ? 44 : 20);
    }
    
    return height;
}

- (void)popupClose:(UIButton *)sender
{
    [_popupWebView removeFromSuperview];
    _popupWebView = nil;
}

- (IBAction)webviewBack:(id)sender
{
    NSURL *urla = webview.URL;
    if([urla.absoluteString rangeOfString:Preferences.sharedPreferences.faxHost].length < 1) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil  message:@"충전하기를 취소하시겠습니까?"
                                       preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleDefault
           handler:^(UIAlertAction * action) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/mypage/charge", Preferences.sharedPreferences.faxURL]];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            [webview loadRequest: request];

        }];
        UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"취소" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        }];

        [alert addAction:cancelAction];
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
    }
    else {
        NSURL *url = [NSURL URLWithString:Preferences.sharedPreferences.faxURL];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

        [webview loadRequest: request];
    }
}

/*- (void)_webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;// https://106.103.233.78/m/security/login

    NSString *url_path = url.path;
//    if([url_path isEqualToString:@"/m"]) {
//
//        [_mainController showSessionOutAlert];
//        decisionHandler(WKNavigationActionPolicyCancel);
//        return;
//    }

    NSString *scheme = url.scheme;
    if([scheme isEqualToString:@"tel"] || [scheme isEqualToString:@"sms"]) {
        [[UIApplication sharedApplication] openURL:url options:[NSDictionary dictionary] completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    NSArray<NSHTTPCookie *> *cookies = NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies;
    WKHTTPCookieStore *cookie_store = _webkitview.configuration.websiteDataStore.httpCookieStore;
    for(int i=0;i<cookies.count;i++) {
        NSHTTPCookie *cookie = cookies[i];
        [cookie_store setCookie:cookie completionHandler:nil];
    }

    NSArray *headerKeys = [navigationAction.request.allHTTPHeaderFields allKeys];
    BOOL hasCookies = [headerKeys containsObject:@"Cookie"];
    if(hasCookies) {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
    else {
        NSMutableURLRequest *req = (NSMutableURLRequest *)navigationAction.request;
        id cookie_dict = [NSHTTPCookie requestHeaderFieldsWithCookies:NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies];
        id headers = req.allHTTPHeaderFields;
        NSArray *keys = [cookie_dict allKeys];
        for(NSString *key in keys) {
            NSString *cookie_str = cookie_dict[key];
            headers[key] =  cookie_str;
        }
        req.allHTTPHeaderFields = headers;
        
        WKWebViewConfiguration *wconf = webview.configuration;
        WKUserContentController *content_cont = wconf.userContentController;
        if([content_cont userScripts].count == 0) {
            [content_cont addUserScript:cookieScript];
        }

        
        [webView loadRequest:req];
        decisionHandler(WKNavigationActionPolicyCancel);
   }
    
    
    //decisionHandler(WKNavigationActionPolicyAllow);
}*/



#pragma mark - Javascript Bridge Methods

- (void)userContentController:(nonnull WKUserContentController *)userContentController didReceiveScriptMessage:(nonnull WKScriptMessage *)message {

    NSString *sel_str = [NSString stringWithFormat:@"%@:",message.name];
    
    NSLog(@"Script Called: %@", sel_str);
    
    SEL bridge_sel = NSSelectorFromString(sel_str);
    [self performSelector:bridge_sel withObject:message.body];
}

- (void)simpeLoginSetup:(id)sender {
   UIStoryboard *s_board = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    SimpleLoginViewController *sc = [s_board instantiateViewControllerWithIdentifier:@"simple"];
    sc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    sc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:sc animated:YES completion:nil];
}

- (void)storeUserInfo:(NSString *)msg {
    NSString *aesvec = [NSString stringWithFormat:@"%@_AESVector", @"WebFaxIOS"];
    NSString *aeskey = [NSString stringWithFormat:@"%@_AESEncKey", @"WebFaxIOS"];
    [Preferences sharedPreferences].userID = [msg AES128EncryptWithKey:aeskey vector:aesvec];
    if(msg.length < 1) {
//        [Preferences sharedPreferences].simpleLogin = nil;
//        [Preferences sharedPreferences].useBioLogin = NO;
//        [Preferences sharedPreferences].useSimple = NO;
//        [[Preferences sharedPreferences] save];
//        WKWebsiteDataStore *dateStore = [WKWebsiteDataStore defaultDataStore];
//        [dateStore
//           fetchDataRecordsOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
//           completionHandler:^(NSArray<WKWebsiteDataRecord *> * __nonnull records) {
//             for (WKWebsiteDataRecord *record  in records) {
//                 [[WKWebsiteDataStore defaultDataStore]
//                     removeDataOfTypes:record.dataTypes
//                     forDataRecords:@[record]
//                     completionHandler:^{
//                     }
//                 ];
//             }
//           }
//        ];
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"" message:@"로그아웃합니다. 다시 실행해 주세요."
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
            exit(1);
        }]];
        [self presentViewController:alertController animated:YES completion:^{}];
    }
    [[Preferences sharedPreferences] save];
}

- (void)openLogin:(id)sender {
    UIStoryboard *s_board = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    SimpleLoginViewController *sc = [s_board instantiateViewControllerWithIdentifier:@"simple"];
    sc.isLogin = YES;
    sc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    sc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:sc animated:YES completion:nil];
}

- (void)openLoginSetup:(id)sender {
    UIStoryboard *s_board = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController *sc = [s_board instantiateViewControllerWithIdentifier:@"loginPreference"];
    sc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    sc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:sc animated:YES completion:nil];
}

- (void)getPhoneImage:(id)sender {
    UIImagePickerController *_imagepickerController = [[UIImagePickerController alloc] init];
    [_imagepickerController setDelegate:self];
    [_imagepickerController setSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
    [self presentViewController:_imagepickerController animated:YES completion:nil];
}

- (void)getCameraImage:(id)sender {
    UIImagePickerController *_imagepickerController = [[UIImagePickerController alloc] init];
    [_imagepickerController setDelegate:self];
    [_imagepickerController setSourceType:UIImagePickerControllerSourceTypeCamera];
    [self presentViewController:_imagepickerController animated:YES completion:nil];
}

-(void)getGcmId:(id)sender {
    NSString* fcmToken = [[PushNotificationManager sharedInstance] getFcmToken];
    
    NSString *scpt = [NSString stringWithFormat:@"setGcmId('%@')", fcmToken];
    
    [self->webview evaluateJavaScript:scpt completionHandler:nil];
}

#pragma mark - UIImagePickerContoller Delegate
- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *img = [info objectForKey:UIImagePickerControllerOriginalImage];
    UIStoryboard *s_board = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    ImageCropViewController *controller = [s_board instantiateViewControllerWithIdentifier:@"cropimage"];
    controller.image = img;
    controller.delegate = self;
    controller.blurredBackground = YES;
    controller.modalPresentationStyle = UIModalPresentationOverFullScreen;
    controller.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self dismissViewControllerAnimated:YES completion:^ {
        [self presentViewController:controller animated:YES completion:NULL];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
}


- (UIImage *)downSampling:(UIImage *)img {
    CGSize imgsize = [img size];
    if(imgsize.width > 2000 || imgsize.height > 2000) {
        CGSize newsize;
        if(imgsize.width > imgsize.height) {
            newsize = CGSizeMake(2000, imgsize.height / imgsize.width * 2000);
        }
        else {
            newsize = CGSizeMake(imgsize.width / imgsize.height * 2000, 2000);
        }
        UIGraphicsBeginImageContext(newsize);
        [img drawInRect:CGRectMake(0, 0, newsize.width, newsize.height)];
        UIImage *destImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return destImage;
    }
    return img;
}

- (void)ImageCropViewControllerSuccess:(ImageCropViewController *)controller didFinishCroppingImage:(UIImage *)image {
    UIView *targetView = nil;
    if (controller.presentedViewController)
    {
        targetView = controller.presentedViewController.view;
    }
    else
    {
        targetView = controller.view;
    }
    HUD = [MBProgressHUD showHUDAddedTo:targetView
                               animated:YES];
    
    UIImage *simage = [self downSampling:image];
    NSData *imageData = UIImageJPEGRepresentation(simage, 0.9);
//    NSData *imageData = UIImagePNGRepresentation(image);
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@/commons/file/uploadForMobile", Preferences.sharedPreferences.faxHost]]];
    [request setHTTPMethod:@"POST"];
    
    NSString *cookie_str = [Preferences sharedPreferences].userID;
    NSString *aesvec = [NSString stringWithFormat:@"%@_AESVector", @"WebFaxIOS"];
    NSString *aeskey = [NSString stringWithFormat:@"%@_AESEncKey", @"WebFaxIOS"];
    cookie_str = [cookie_str AES128DecryptWithKey:aeskey vector:aesvec];
    NSUInteger index = [cookie_str rangeOfString:@":"].location;
    if(index > 0) cookie_str = [NSString stringWithFormat:@"magicfaxUserId=%@", [cookie_str substringToIndex:index]];
    id cookie_dict = [NSHTTPCookie requestHeaderFieldsWithCookies:NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies];
    NSArray *keys = [cookie_dict allKeys];
    for(NSString *key in keys) {
        if([key isEqualToString:@"Cookie"]) {
            NSString *sid_str = cookie_dict[key];
            cookie_str = [NSString stringWithFormat:@"%@;%@",sid_str, cookie_str];
        }
    }
    [request addValue:cookie_str forHTTPHeaderField: @"Cookie"];

    NSMutableData *body = [NSMutableData data];
    NSString *boundary = @"unique-consistent-string";
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
    [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
    
    NSMutableString *para_str = [NSMutableString string];
    [para_str appendFormat:@"\r\n--%@\r\n",boundary];
    [para_str appendString:@"Content-Disposition: form-data; name=\"inputName\"\r\n\r\n"];
    [para_str appendString:@"file\r\n"];
    
    [para_str appendFormat:@"--%@\r\n",boundary];
    [para_str appendString:@"Content-Disposition: form-data; name=\"dirName\"\r\n\r\n"];
    [para_str appendString:@"/upload_fax/web\r\n"];

    [para_str appendFormat:@"--%@\r\n",boundary];
    [para_str appendString:@"Content-Disposition: form-data; name=\"fileNameReal\"\r\n\r\n"];
    [para_str appendFormat:@"%@\r\n", @"ios_cropped.jpg"];

    
    [para_str appendFormat:@"--%@\r\n",boundary];
    [para_str appendFormat:@"Content-Disposition: form-data; name=\"file\";filename=\"%@\"\r\n", @"ios_cropped.jpg"];
    [para_str appendString:@"Content-Type: image/jpeg\r\n\r\n"];
//    [para_str appendString:@"Content-Disposition: form-data; name=\"binaryFile\"\r\n"];
//    [para_str appendString:@"Content-Type: image/jpg\r\n"];
//    [para_str appendString:@"Content-Transfer-Encoding: binary\r\n\r\n"];

    [body appendData:[para_str dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[NSData dataWithData:imageData]];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [request addValue:[NSString stringWithFormat:@"%d",(int)body.length] forHTTPHeaderField: @"Content-Length"];

    [request setHTTPBody:body];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    
    NSURLSessionDataTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (result) {
                if ([[result objectForKey:@"result"] isEqualToString:@"success"]) {
                    NSString *scpt = [NSString stringWithFormat:@"attachFileFromPhone('%@', '%@', %@)",[result objectForKey:@"originalName"], [result objectForKey:@"path"], [result objectForKey:@"size"]];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        id pvc = controller.presentingViewController;
                        [pvc dismissViewControllerAnimated:YES completion:^ {
                            [self->webview evaluateJavaScript:scpt completionHandler:^(id _Nullable res, NSError * _Nullable error) {
                            }];
                            [self->HUD hideAnimated:YES];
                        }];
                    });
                }
                else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@""
                                                                                                 message:[result objectForKey:@"message"]
                                                                                          preferredStyle:UIAlertControllerStyleAlert];
                        [alertController addAction:[UIAlertAction actionWithTitle:@"확인" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
                        }]];
                        [controller presentViewController:alertController animated:YES completion:^{}];
                        [self->HUD hideAnimated:YES];
                    });
                }
            }
            else
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->HUD hideAnimated:YES];
                    id pvc = controller.presentingViewController;
                    [pvc dismissViewControllerAnimated:YES completion:^ {
                    }];
                });
            }
        }
        else
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->HUD hideAnimated:YES];
                id pvc = controller.presentingViewController;
                [pvc dismissViewControllerAnimated:YES completion:^ {
                }];
            });
        }
        dispatch_semaphore_signal(sem);
    }];
    [dataTask resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
}

- (void)ImageCropViewControllerDidCancel:(ImageCropViewController *)controller{
    id pvc = controller.presentingViewController;
    [pvc dismissViewControllerAnimated:YES completion:^ {
    }];
}

- (void)myTask {
    // Do something usefull in here instead of sleeping ...
}

@end
