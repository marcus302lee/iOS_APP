//
//  Preferences.m
//  WebFax2
//
//  Created by Seungil Shin on 2021/06/13.
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "Preferences.h"

@implementation Preferences
//@synthesize userID, userPW, companyID;

#define PREF_USERID             @"UserID"
#define PREF_USERPW             @"UserPW"
#define PREF_BIO                @"BIOLogin"
#define PREF_SIMPLE             @"SimpleLogin"
#define PREF_SIMPLELOGIN        @"SimpleLoginNo"
#define PREF_PERMISSION         @"ShowPermission"

// Keychain 식별 상수
#define KEYCHAIN_SERVICE        @"com.uplus.webfax"
#define KEYCHAIN_ACCOUNT        @"simpleLoginPIN"


Preferences *shared_preferences = nil;

+ (Preferences *)sharedPreferences
{
    if(shared_preferences == nil) {
        shared_preferences = [[Preferences alloc] init];
    }
    return shared_preferences;
}

+ (void)updateString:(NSString *)str forKey:(NSString *)key userDefault:(NSUserDefaults *)def
{
    if(str && str.length > 0) {
        [def setObject:str forKey:key];
    }
    else {
        [def removeObjectForKey:key];
    }
}

+ (void)updateValue:(NSNumber *)num forKey:(NSString *)key userDefault:(NSUserDefaults *)def
{
    if(num && [num intValue] > 0) {
        [def setObject:num forKey:key];
    }
    else {
        [def removeObjectForKey:key];
    }
}

+ (void)updaeBool:(BOOL)val forKey:(NSString *)key userDefault:(NSUserDefaults *)def
{
    [def setBool:val forKey:key];
}

// Keychain에 간편 로그인 PIN 저장
// value가 nil이면 Keychain 항목을 삭제 (비밀번호 초기화)
+ (void)saveToKeychain:(NSString *)value
{
    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: KEYCHAIN_SERVICE,
        (__bridge id)kSecAttrAccount: KEYCHAIN_ACCOUNT
    };
    // 기존 항목 먼저 삭제
    SecItemDelete((__bridge CFDictionaryRef)query);

    if (!value) return; // nil이면 삭제만 수행

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *item = [query mutableCopy];
    // 기기 잠금 해제 시에만 접근 가능, 기기 이전(백업/복원) 불가 설정
    item[(__bridge id)kSecValueData]      = data;
    item[(__bridge id)kSecAttrAccessible] =
        (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
    SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

// Keychain에서 간편 로그인 PIN 로드
// 항목이 없으면 nil 반환
+ (NSString *)loadFromKeychain
{
    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: KEYCHAIN_SERVICE,
        (__bridge id)kSecAttrAccount: KEYCHAIN_ACCOUNT,
        (__bridge id)kSecReturnData:  @YES,
        (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitOne
    };
    CFDataRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query,
                                          (CFTypeRef *)&result);
    if (status != errSecSuccess || !result) return nil;
    return [[NSString alloc] initWithData:(__bridge_transfer NSData *)result
                                 encoding:NSUTF8StringEncoding];
}

- init {
    self = [super init];
    if(self) {
        NSUserDefaults *std_def = [NSUserDefaults standardUserDefaults];
        self.userID        = [std_def stringForKey:PREF_USERID];
        self.userPW        = [std_def stringForKey:PREF_USERPW];
        self.useBioLogin   = [std_def boolForKey:PREF_BIO];
        self.useSimple     = [std_def boolForKey:PREF_SIMPLE];
        self.showPermission = [std_def boolForKey:PREF_PERMISSION];

        // Keychain에서 PIN 로드 시도
        NSString *keychainPIN = [Preferences loadFromKeychain];
        if (keychainPIN) {
            // Keychain에 이미 저장된 경우 그대로 사용
            self.simpleLogin = keychainPIN;
        } else {
            // 마이그레이션: 구버전 NSUserDefaults 평문 값이 있으면 Keychain으로 이전
            NSString *legacyPIN = [std_def stringForKey:PREF_SIMPLELOGIN];
            if (legacyPIN) {
                [Preferences saveToKeychain:legacyPIN];        // Keychain에 저장
                [std_def removeObjectForKey:PREF_SIMPLELOGIN]; // 평문 데이터 삭제
                [std_def synchronize];
                self.simpleLogin = legacyPIN;
            }
            // legacyPIN도 없으면 simpleLogin은 nil (최초 설치 상태)
        }
    }
    return self;
}

- (void)save
{
    NSUserDefaults *std_def = [NSUserDefaults standardUserDefaults];
    [Preferences updateString:self.userID    forKey:PREF_USERID    userDefault:std_def];
    [Preferences updateString:self.userPW    forKey:PREF_USERPW    userDefault:std_def];
    [Preferences updaeBool:self.useBioLogin  forKey:PREF_BIO       userDefault:std_def];
    [Preferences updaeBool:self.useSimple    forKey:PREF_SIMPLE    userDefault:std_def];
    [Preferences updaeBool:self.showPermission forKey:PREF_PERMISSION userDefault:std_def];
    // simpleLogin은 NSUserDefaults 대신 Keychain에 저장
    [Preferences saveToKeychain:self.simpleLogin];

    [std_def synchronize];
}

- (NSString *)faxURL
{
    NSDictionary *infoDic = [[NSBundle mainBundle] infoDictionary];
    NSString *server_url = [infoDic objectForKey:@"ServerURL"];
    return [NSString stringWithFormat:@"https://%@/m", server_url];
}

- (NSString *)faxHost
{
    NSDictionary *infoDic = [[NSBundle mainBundle] infoDictionary];
    return [infoDic objectForKey:@"ServerURL"];
}

@end
