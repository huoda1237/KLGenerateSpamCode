//
//  main.m
//  generateSpamCode
//
//  Created by 柯磊 on 2017/7/5.
//  Copyright © 2017年 GAEA. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <stdlib.h>
#import  <objc/runtime.h>

// 命令行修改工程目录下所有 png 资源 hash 值
// 使用 ImageMagick 进行图片压缩，所以需要安装 ImageMagick，安装方法 brew install imagemagick
// find . -iname "*.png" -exec echo {} \; -exec convert {} {} \;
// or
// find . -iname "*.png" -exec echo {} \; -exec convert {} -quality 95 {} \;

typedef NS_ENUM(NSInteger, GSCSourceType) {
    GSCSourceTypeClass,
    GSCSourceTypeCategory,
};

void recursiveDirectory(NSString *directory, NSArray<NSString *> *ignoreDirNames, void(^handleMFile)(NSString *mFilePath), void(^handleSwiftFile)(NSString *swiftFilePath));
void generateSpamCodeFile(NSString *outDirectory, NSString *mFilePath, GSCSourceType type, NSMutableString *categoryCallImportString, NSMutableString *categoryCallFuncString, NSMutableString *newClassCallImportString, NSMutableString *newClassCallFuncString);
void generateSwiftSpamCodeFile(NSString *outDirectory, NSString *swiftFilePath);
NSString *randomString(NSInteger length);
void handleXcassetsFiles(NSString *directory);
void deleteComments(NSString *directory, NSArray<NSString *> *ignoreDirNames);
void modifyProjectName(NSString *projectDir, NSString *oldName, NSString *newName);
void modifyClassNamePrefix(NSMutableString *projectContent, NSString *sourceCodeDir, NSArray<NSString *> *ignoreDirNames, NSString *oldName, NSString *newName);
void getAllCategory(NSMutableString *projectContent, NSString *sourceCodeDir, NSArray<NSString *> *ignoreDirNames, NSString *oldName, NSString *newName);
NSString * createSingleProperty(void);
NSString * createMuchProperty(void);
NSString * createMethod(void);
NSString * clasStr(void);
void createNewFile(NSString *outDirectory);
void addMethodToMFile(NSString *sourceCodeDir,NSArray<NSString *> *ignoreDirNames);
NSString * createSingleMethod(void);
void addPropertytoOriginalFile(NSString *sourceCodeDir,NSArray<NSString *> *ignoreDirNames);
void getMethodBackType(NSString *sourceCodeDir,NSArray<NSString *> *ignoreDirNames);
void changeDirectorName (NSString *sourceCodeDir,NSArray<NSString *> *ignoreDirNames);

NSString *gOutParameterName = nil;
NSString *gSpamCodeFuncationCallName = nil;
NSString *gNewClassFuncationCallName = nil;
NSString *gSourceCodeDir = nil;
NSString *gOriginFileName = nil;
NSMutableArray *categoryArr = nil;
NSArray *chartArray = nil;
NSArray *backArray = nil;
NSArray *propertyArray = nil;
NSMutableArray *methodPreArr = nil;
NSArray *allSearchArray = nil;

static NSString * const kNewClassDirName = @"NewClass";

#pragma mark - 公共方法

static const NSString *kRandomAlphabet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
NSString *randomString(NSInteger length) {
    NSMutableString *ret = [NSMutableString stringWithCapacity:length];
    for (int i = 0; i < length; i++) {
        [ret appendFormat:@"%C", [kRandomAlphabet characterAtIndex:arc4random_uniform((uint32_t)[kRandomAlphabet length])]];
    }
    return ret;
}

NSString *randomLetter() {
    return [NSString stringWithFormat:@"%C", [kRandomAlphabet characterAtIndex:arc4random_uniform(52)]];
}

NSRange getOutermostCurlyBraceRange(NSString *string, unichar beginChar, unichar endChar, NSInteger beginIndex) {
    NSInteger braceCount = -1;
    NSInteger endIndex = string.length - 1;
    for (NSInteger i = beginIndex; i <= endIndex; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == beginChar) {
            braceCount = ((braceCount == -1) ? 0 : braceCount) + 1;
        } else if (c == endChar) {
            braceCount--;
        }
        if (braceCount == 0) {
            endIndex = i;
            break;
        }
    }
    return NSMakeRange(beginIndex + 1, endIndex - beginIndex - 1);
}

NSString * getSwiftImportString(NSString *string) {
    NSMutableString *ret = [NSMutableString string];
    
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^ *import *.+" options:NSRegularExpressionAnchorsMatchLines|NSRegularExpressionUseUnicodeWordBoundaries error:nil];
    
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *importRow = [string substringWithRange:obj.range];
        [ret appendString:importRow];
        [ret appendString:@"\n"];
    }];
    
    return ret;
}

BOOL regularReplacement(NSMutableString *originalString, NSString *regularExpression, NSString *newString) {
    __block BOOL isChanged = NO;
    BOOL isGroupNo1 = [newString isEqualToString:@"\\1"];
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regularExpression options:NSRegularExpressionAnchorsMatchLines|NSRegularExpressionUseUnixLineSeparators error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:originalString options:0 range:NSMakeRange(0, originalString.length)];
    [matches enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!isChanged) {
            isChanged = YES;
        }
        if (isGroupNo1) {
            NSString *withString = [originalString substringWithRange:[obj rangeAtIndex:1]];
            [originalString replaceCharactersInRange:obj.range withString:withString];
        } else {
            [originalString replaceCharactersInRange:obj.range withString:newString];
        }
    }];
    return isChanged;
}

void renameFile(NSString *oldPath, NSString *newPath) {

    NSError *error;
    [[NSFileManager defaultManager] moveItemAtPath:oldPath toPath:newPath error:&error];
    if (error) {
        printf("修改文件名称失败。\n  oldPath=%s\n  newPath=%s\n  ERROR:%s\n", oldPath.UTF8String, newPath.UTF8String, error.localizedDescription.UTF8String);
        abort();
    }
}

#pragma mark - 主入口

int main(int argc, const char * argv[]) {
    
    @autoreleasepool {
        allSearchArray = @[@"- (void)",@"+ (instancetype)",@"+ (void)",@"+ (PHAssetCollection *)",@"- (NSString *)",@"+(NSURLSessionTask *)",@"+(void)",@"+ (BOOL)",@"+ (NSString *)",@"+ (NSMutableArray *)",@"+(BOOL)",@"- (instancetype)",@"-(void)",@"- (id)",@"+(NSDictionary *)",@"+(NSString *)",@"+(NSArray *)",@"+ (NSDate *)",@"+ (UIViewController *)",@"+ (UIImage *)",@"- (NSMutableDictionary *)",@"+(instancetype)",@"+ (NSDictionary *)",@"+ (id)",@"- (UIImageView *)",@"- (UIButton *)",@"- (WKWebView *)",@"-(NSMutableArray *)",@"-(BOOL)",@"-(UITableViewCell *)",@"-(UIView *)",@"-(UIViewController *)",@"- (UIViewController *)",@"-(NSMutableData *)",@"-(dispatch_queue_t)",@"- (NSData *)",@"- (NSDictionary *)",@"+ (ambaStateMachine *)",@"-(NSThread *)",@"- (nullable UIImage *)",@"- (BOOL)",@"- (CMTime)",@"- (UIInterfaceOrientationMask)",@"- (UIInterfaceOrientation)",@"- (IBAction)",@"- (UICollectionViewCell *)",@"+ (Class)",@"-(NSString *)",@"- (UIStackView *)",@"- (NSArray *)",@"- (id<NSCoding>)",@"+ (NSData *)",@"- (sqlite3_stmt *)",@"- (NSMutableArray *)",@"+ (NSError *)",@"- (Class)",@"+ (NSMutableDictionary *)",@"- (NSURL *)",@"+ (NSSet *)",@"- (nonnull CLLocation *)",@"+ (nullable CLLocation *)",@"- (UIColor *)",@"- (dispatch_queue_t)",@"- (NSError *)",@"- (CFReadStreamRef)",@"- (CFWriteStreamRef)",@"+ (nullable instancetype)",@"+ (NSURL *)",@"-(instancetype)",@"- (FMDatabase*)",@"- (NSError*)",@"- (FMResultSet *)",@"- (NSString*)",@"- (NSData*)",@"- (NSDate*)",@"- (FMResultSet*)",@"- (FMStatement*)",@"- (NSDate *)",@"+ (NSString*)",@"+ (NSDateFormatter *)",@"- (NSDictionary*)",@"+(id)",@"- (UILabel *)",@"- (UIView *)",@"- (CAGradientLayer *)",@"- (CAShapeLayer *)",@"- (UITableView *)",@"- (UIScrollView *)",@"- (UITableViewCell *)",@"-(NSLock *)",@"-(NSCondition *)",@"- (UICollectionView *)",@"- (CFYPanoramaView *)",@"- (CFYTimeDelayView *)",@"- (ZJSettingsTypeModel *)",@"- (CFYTimeDelayIntroduceView *)",@"-(NSArray *)",@"- (MKAnnotationView *)",@"- (MKOverlayRenderer *)",@"-(ZJFlyModeManagerView *)",@"-(TispView*) ",@"-(UIImageView *)",@"- (NSMutableArray*)",@"- (CFYTimerTool *)",@"-(UIImage *)",@"- (CFYButton *)",@"-(id)",@"- (NSMutableAttributedString *)",@"- (NSArray*)",@"+ (UIColor*)",@"+ (NSArray *)",@"-(UILabel *)",@"-(UIButton *)",@"-(UICollectionView *)",@"- (UIActivityIndicatorView *)",@"-(void )",@"-(NSString*)",@"- (ALAssetsLibrary *)",@"- (PHAssetCollection *)",@"- (NSMutableData *)",@"-(NSData *)",@"- (void )",@"-(NSMutableArray*)",@"-(UICollectionViewCell *)",@"-(UIEdgeInsets)",@"-(UITableViewCellEditingStyle)",@"- (UICollectionReusableView *)",@"- (UIBezierPath *)",@"+ (UIFont*)",@"+ (UILabel*)",@"+ (UIImage*)",@"- (CAShapeLayer*)",@"- (UIColor*)",@"- (UIImage*)",@"- (UIControl*)",@"- (UIView*)",@"- (UILabel*)",@"- (UIImageView*)",@"- (NSAttributedString *)",@"- (UIToolbar *)",@"- (UIBarButtonItem *)",@"- (UIFont *)",@"-(CABasicAnimation *)",@"+ (AppDelegate *)",@"- (UIImage *)",@"+ (UIEdgeInsets)",@"-(MKOverlayRenderer *)",@"+ (NSArray<NSString *> *)",@"-(AVMutableComposition *)",@"-(NSURL *)",@"+ (cv::Mat)",@"- (CVPixelBufferRef)",@"-(cv::Mat)",@"- (cv::Mat)",@"+ (CVPixelBufferRef)",@"-(UIImage*)",@"+ (UIColor *)",@"+ (UIStatusBarStyle)",@"- (dispatch_source_t)",@"-(NSMutableDictionary *)",@"- (NSURLSessionDownloadTask *)",@"-(MKCoordinateRegion)",@"- (MKCoordinateSpan)"];
        methodPreArr = [NSMutableArray new];
        chartArray = @[@"A",@"B",@"C",@"D",@"E",@"F",@"G",@"H",@"I",@"J",@"K",@"L",@"M",@"N",@"O",@"P",@"Q",@"R",@"S",@"T",@"U",@"V",@"W",@"X",@"Y",@"Z",@"a",@"b",@"c",@"d",@"e",@"f",@"g",@"h",@"i",@"j",@"k",@"l",@"m",@"n",@"o",@"p",@"q",@"r",@"s",@"t",@"u",@"v",@"w",@"x",@"y",@"z",@"0",@"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8",@"9",@"_",@"Cfy",@"Cfly",@"Cfly2",@"Ctu",@"Start",@"Fly",@"Num",@"ChangTu",@"ZhiNeng",@"GuangZhou",@"Drone"];
        backArray =  @[@"NSArray",@"NSDictionary",@"NSString"];
        propertyArray = @[@"UIButton",@"UITableView",@"UILabel",@"UIView",@"NSInteger",@"int",@"BOOL",@"NSString",@"NSDictionary",@"NSArray",@"NSMutableArray"];
        
        categoryArr = [[NSMutableArray alloc] init];
        
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        NSLog(@"获取的设置是：%@",arguments);
        if (!arguments || arguments.count <= 1) {
            printf("缺少工程目录参数\n");
            return 1;
        }
        if (arguments.count <= 2) {
            printf("缺少任务参数 -spamCodeOut or -handleXcassets or -deleteComments\n");
            return 1;
        }
        
        BOOL isDirectory = NO;
        NSString *outDirString = nil;
        NSArray<NSString *> *ignoreDirNames = nil;
        BOOL needHandleXcassets = NO;
        BOOL needDeleteComments = NO;
        NSString *oldProjectName = nil;
        NSString *newProjectName = nil;
        NSString *projectFilePath = nil;
        NSString *oldClassNamePrefix = nil;
        NSString *newClassNamePrefix = nil;
        NSString *changeDirName = nil;
        
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSInteger i = 1; i < arguments.count; i++) {
            NSString *argument = arguments[i];
            if (i == 1) {
                gSourceCodeDir = argument;
                if (![fm fileExistsAtPath:gSourceCodeDir isDirectory:&isDirectory]) {
                    printf("%s不存在\n", [gSourceCodeDir UTF8String]);
                    return 1;
                }
                if (!isDirectory) {
                    printf("%s不是目录\n", [gSourceCodeDir UTF8String]);
                    return 1;
                }
                continue;
            }
            
            if ([argument isEqualToString:@"-handleXcassets"]) {
                needHandleXcassets = YES;
                continue;
            }
            if ([argument isEqualToString:@"-deleteComments"]) {
                needDeleteComments = YES;
                continue;
            }
            if ([argument isEqualToString:@"-modifyProjectName"]) {
                NSString *string = arguments[i+1];
                NSArray<NSString *> *names = [string componentsSeparatedByString:@">"];
                if (names.count < 2) {
                    printf("修改工程名参数错误。参数示例：CCApp>DDApp，传入参数：%s\n", string.UTF8String);
                    return 1;
                }
                oldProjectName = names[0];
                newProjectName = names[1];
                if (oldProjectName.length <= 0 || newProjectName.length <= 0) {
                    printf("修改工程名参数错误。参数示例：CCApp>DDApp，传入参数：%s\n", string.UTF8String);
                    return 1;
                }
                continue;
            }
            
            if ([argument isEqualToString:@"-originFileName"]) {
                gOriginFileName = arguments[i+1];
                continue;
            }
            
            if ([argument isEqualToString:@"-modifyClassNamePrefix"]) {
                NSString *string = arguments[i+1];
                projectFilePath = [string stringByAppendingPathComponent:@"project.pbxproj"];
                if (![fm fileExistsAtPath:string isDirectory:&isDirectory] || !isDirectory
                    || ![fm fileExistsAtPath:projectFilePath isDirectory:&isDirectory] || isDirectory) {
                    printf("修改类名前缀的工程文件参数错误。%s", string.UTF8String);
                    return 1;
                }
                
                string = arguments[i+2];
                NSArray<NSString *> *names = [string componentsSeparatedByString:@">"];
                if (names.count < 2) {
                    printf("修改类名前缀参数错误。参数示例：CC>DD，传入参数：%s\n", string.UTF8String);
                    return 1;
                }
                oldClassNamePrefix = names[0];
                newClassNamePrefix = names[1];
                if (oldClassNamePrefix.length <= 0 || newClassNamePrefix.length <= 0) {
                    printf("修改类名前缀参数错误。参数示例：CC>DD，传入参数：%s\n", string.UTF8String);
                    return 1;
                }
                continue;
            }
            if ([argument isEqualToString:@"-spamCodeOut"]) {
                outDirString = arguments[i+1];
                if ([fm fileExistsAtPath:outDirString isDirectory:&isDirectory]) {
                    if (!isDirectory) {
                        printf("%s 已存在但不是文件夹，需要传入一个输出文件夹目录\n", [outDirString UTF8String]);
                        return 1;
                    }
                } else {
                    NSError *error = nil;
                    if (![fm createDirectoryAtPath:outDirString withIntermediateDirectories:YES attributes:nil error:&error]) {
                        printf("创建输出目录失败，请确认 -spamCodeOut 之后接的是一个“输出文件夹目录”参数，错误信息如下：\n传入的输出文件夹目录：%s\n%s\n", [outDirString UTF8String], [error.localizedDescription UTF8String]);
                        return 1;
                    }
                }
                
                NSString *newClassOutDirString = [outDirString stringByAppendingPathComponent:kNewClassDirName];
                if ([fm fileExistsAtPath:newClassOutDirString isDirectory:&isDirectory]) {
                    if (!isDirectory) {
                        printf("%s 已存在但不是文件夹\n", [newClassOutDirString UTF8String]);
                        return 1;
                    }
                } else {
                    NSError *error = nil;
                    if (![fm createDirectoryAtPath:newClassOutDirString withIntermediateDirectories:YES attributes:nil error:&error]) {
                        printf("创建输出目录 %s 失败", [newClassOutDirString UTF8String]);
                        return 1;
                    }
                }
                
                if (i < arguments.count) {
                    gOutParameterName = @"good";
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[a-zA-Z]+" options:0 error:nil];
                    if ([regex numberOfMatchesInString:gOutParameterName options:0 range:NSMakeRange(0, gOutParameterName.length)] <= 0) {
                        printf("缺少垃圾代码参数名，或参数名\"%s\"不合法(需要字母开头)\n", [gOutParameterName UTF8String]);
                        return 1;
                    }
                } else {
                    printf("缺少垃圾代码参数名，参数名需要根在输出目录后面\n");
                    return 1;
                }
                
                if (i < arguments.count) {
                    gSpamCodeFuncationCallName = @"zero";
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[a-zA-Z]+" options:0 error:nil];
                    if ([regex numberOfMatchesInString:gSpamCodeFuncationCallName options:0 range:NSMakeRange(0, gSpamCodeFuncationCallName.length)] <= 0) {
                        printf("缺少垃圾代码函数调用名，或参数名\"%s\"不合法(需要字母开头)\n", [gSpamCodeFuncationCallName UTF8String]);
                        return 1;
                    }
                }
                
                if (i < arguments.count) {
                    gNewClassFuncationCallName = @"happy";
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[a-zA-Z]+" options:0 error:nil];
                    if ([regex numberOfMatchesInString:gNewClassFuncationCallName options:0 range:NSMakeRange(0, gNewClassFuncationCallName.length)] <= 0) {
                        printf("缺少 NewClass 代码函数调用名，或参数名\"%s\"不合法(需要字母开头)\n", [gNewClassFuncationCallName UTF8String]);
                        return 1;
                    }
                }
                continue;
            }
            if ([argument isEqualToString:@"-ignoreDirNames"]) {
                ignoreDirNames = [arguments[i+1] componentsSeparatedByString:@","];
                NSLog(@"忽略的文件夹：%@",ignoreDirNames);
                continue;
            }
            
            if ([argument isEqualToString:@"-changeDirectorName"]) {
                changeDirName = arguments[1+i];
                NSLog(@"修改哪个文件夹下文件名称：%@",changeDirName);
                continue;
            }
        }
        
        
        //下面两个方法是辅助使用的，正式混淆的时候不需要使用
        //获取文件中的所有分类（单独获取用，在混淆是做参考使用）（//判断是不是类别 ，如果是uiview+这种系统的类别的话则不去修改类名，否则去修改类名）
//        @autoreleasepool {
//            NSError *error = nil;
//            NSMutableString *projectContent = [NSMutableString stringWithContentsOfFile:projectFilePath encoding:NSUTF8StringEncoding error:&error];
//            if (error) {
//                printf("打开工程文件 %s 失败：%s\n", projectFilePath.UTF8String, error.localizedDescription.UTF8String);
//                return 1;
//            }
//            getAllCategory(projectContent, gSourceCodeDir, ignoreDirNames, oldClassNamePrefix, newClassNamePrefix);
//        }
        
        //获取所有的方法前部分
//        @autoreleasepool {
//            getMethodBackType(gSourceCodeDir,ignoreDirNames);
//        }
//        for (NSString *str in methodPreArr) {
//            printf("%s\n",str.UTF8String);
////            NSLog(@"获取的浅醉是：%@",str);
//        }
        
        
        
        
        
        
        
        
        
        
        
////        修改图片的中名称
//        if (needHandleXcassets) {
//            @autoreleasepool {
//                handleXcassetsFiles(gSourceCodeDir);
//            }
//            printf("修改 Xcassets 中的图片名称完成\n");
//        }
////
////        //删除注释和空行
//        if (needDeleteComments) {
//            @autoreleasepool {
//                deleteComments(gSourceCodeDir, ignoreDirNames);
//            }
//            printf("删除注释和空行完成\n");
//        }
//
//        //修改类名前缀
//        if (oldClassNamePrefix && newClassNamePrefix) {
//            printf("开始修改类名前缀...\n");
//            @autoreleasepool {
//                NSError *error = nil;
//                NSMutableString *projectContent = [NSMutableString stringWithContentsOfFile:projectFilePath encoding:NSUTF8StringEncoding error:&error];
//                NSLog(@"修改后缀名文件长度是：%lu",(unsigned long)projectContent.length);
//                if (error) {
//                    printf("打开工程文件 %s 失败：%s\n", projectFilePath.UTF8String, error.localizedDescription.UTF8String);
//                    return 1;
//                }
//                NSLog(@"修改浅前缀需要忽略的文件是：%@",ignoreDirNames);
//                modifyClassNamePrefix(projectContent, gSourceCodeDir, ignoreDirNames, oldClassNamePrefix, newClassNamePrefix);
//                [projectContent writeToFile:projectFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
//            }
//            printf("修改类名前缀完成\n");
//        }
//
//        //修改工程名称
//        if (oldProjectName && newProjectName) {
//            @autoreleasepool {
//                NSString *dir = [NSString stringWithFormat:@"%@/%@",gSourceCodeDir,gOriginFileName];
//                NSLog(@"开始修改工程名称：%@======%@",dir,gSourceCodeDir);
//                modifyProjectName(dir, oldProjectName, newProjectName);
//            }
//            printf("修改工程名完成\n");
//        }
        
       
//        向原始M文件中添加方法，在每一个方法前添加一个新的方法
//        @autoreleasepool {
//            addMethodToMFile(gSourceCodeDir,ignoreDirNames);
//        }
//        NSLog(@"方法添加完成");
        
        
//        向原始H文件中添加随机数量的属性
//        @autoreleasepool {
//            addPropertytoOriginalFile(gSourceCodeDir,ignoreDirNames);
//        }
//        NSLog(@"属性添加完成");
        
        //修改文件夹名（这个最好是手动来修改，最容易出问题）（如果修改了pch所在的文件夹名称，则需要将pch放在工程目录下，这样就不会报错了）
//        @autoreleasepool {
//            changeDirectorName(changeDirName,ignoreDirNames);
//        }
//        NSLog(@"文件夹名称修改完成");
        
//        生成200个新文件,并在文件中生成新的随机数量的方法和随机数量的属性
//        if (outDirString) {
//            for (int i = 0; i < 200; i ++) {
//                @autoreleasepool {
//                    createNewFile(outDirString);
//                }
//            }
//        }
        
        
        
        //生成垃圾代码（这个可以注释不要）
//        if (outDirString) {
//            NSMutableString *categoryCallImportString = [NSMutableString string];
//            NSMutableString *categoryCallFuncString = [NSMutableString string];
//            NSMutableString *newClassCallImportString = [NSMutableString string];
//            NSMutableString *newClassCallFuncString = [NSMutableString string];
//
//            recursiveDirectory(gSourceCodeDir, ignoreDirNames, ^(NSString *mFilePath) {
//                @autoreleasepool {
//                    generateSpamCodeFile(outDirString, mFilePath, GSCSourceTypeClass, categoryCallImportString, categoryCallFuncString, newClassCallImportString, newClassCallFuncString);
//                    generateSpamCodeFile(outDirString, mFilePath, GSCSourceTypeCategory, categoryCallImportString, categoryCallFuncString, newClassCallImportString, newClassCallFuncString);
//                }
//            }, ^(NSString *swiftFilePath) {
//                @autoreleasepool {
//                    generateSwiftSpamCodeFile(outDirString, swiftFilePath);
//                }
//            });
//
//            NSString *fileName = [gOutParameterName stringByAppendingString:@"CallHeader.h"];
//            NSString *fileContent = [NSString stringWithFormat:@"%@\n%@return ret;\n}", categoryCallImportString, categoryCallFuncString];
//            [fileContent writeToFile:[outDirString stringByAppendingPathComponent:fileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
//
//            fileName = [kNewClassDirName stringByAppendingString:@"CallHeader.h"];
//            fileContent = [NSString stringWithFormat:@"%@\n%@return ret;\n}", newClassCallImportString, newClassCallFuncString];
//            [fileContent writeToFile:[[outDirString stringByAppendingPathComponent:kNewClassDirName] stringByAppendingPathComponent:fileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
//
//            printf("生成垃圾代码完成\n");
//        }
    }
    return 0;
}


#pragma mark 修改文件夹名称
void changeDirectorName (NSString *sourceCodeDir,NSArray<NSString *> *ignoreDirNames){
    NSFileManager *fm = [NSFileManager defaultManager];
    // 遍历源代码文件 h 与 m 配对，swift
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:sourceCodeDir error:nil];
    BOOL isDirectory;
    for (NSString *filePath in files) {
        NSString *path = [sourceCodeDir stringByAppendingPathComponent:filePath];
        NSLog(@"文件地址：%@\n",path);
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            if (![ignoreDirNames containsObject:filePath]) {
                NSArray *array = [filePath componentsSeparatedByString:@"."];
                if (array.count > 1) {
                    //有后缀不修改
                    changeDirectorName(path, ignoreDirNames);
                } else {
                    int randomNum = arc4random() % 20 + 5;
                    NSString *str = @"";
                    for (int i  = 0; i < randomNum; i ++) {
                        str = [NSString stringWithFormat:@"%@%@",str,chartArray[arc4random()%chartArray.count]];
                    }
                    NSString *path_new = [sourceCodeDir stringByAppendingPathComponent:str];
                    renameFile(path, path_new);
                    changeDirectorName(path_new, ignoreDirNames);
                }
            }
            continue;
        }
    }
}

#pragma mark 向原始的H文件中添加属性
void addPropertytoOriginalFile(NSString *sourceCodeDir,NSArray<NSString *> *ignoreDirNames) {
    NSFileManager *fm = [NSFileManager defaultManager];
    // 遍历源代码文件 h 与 m 配对，swift
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:sourceCodeDir error:nil];
    BOOL isDirectory;
    for (NSString *filePath in files) {
        NSString *path = [sourceCodeDir stringByAppendingPathComponent:filePath];
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            if (![ignoreDirNames containsObject:filePath]) {
                addPropertytoOriginalFile(path, ignoreDirNames);
            }
            continue;
        }
        //判断文件是不是存在，存在的话且不是扩展才去添加属性
        if (([filePath hasSuffix:@".mm"] || [filePath hasSuffix:@".m"]) && ![filePath containsString:@"+"]) {
            NSString *hPath = [NSString stringWithFormat:@"%@.h",path.stringByDeletingPathExtension];
            if ([fm fileExistsAtPath:hPath]) {
                //有这个h文件
                NSString *content = [NSString stringWithContentsOfFile:hPath encoding:NSUTF8StringEncoding error:nil];
                NSMutableArray *rangeArr = [NSMutableArray new];
                NSArray *searchArr = @[@"@end"];
                for (NSString *searchStr in searchArr) {
                    NSRange range = [content rangeOfString:searchStr];
                    while (range.location != NSNotFound || range.length != 0) {
                        NSLog(@"获取的范围值：%@",NSStringFromRange(range));
                        [rangeArr addObject:NSStringFromRange(range)];
                        NSUInteger hadSearchedRange = range.location + range.length;
                        NSRange resetRange = NSMakeRange(hadSearchedRange, content.length - hadSearchedRange);
                        range = [content rangeOfString:searchStr options:NSCaseInsensitiveSearch range:resetRange];
                    }
                }
                
                
                NSString *finishstr = @"";
                for (int i = 0; i < rangeArr.count; i ++) {
                    NSString *rangeStr = rangeArr[i];
                    NSRange range = NSRangeFromString(rangeStr);
                    //先插入当前位置之前的内容
                    if (i == 0) {
                        //因为创建的属性会有UI类型，所以需要添加这个包
                        if (![content containsString:@"UIKit/UIKit.h"]) {
                            finishstr = @"#import <UIKit/UIKit.h>\n";
                        }
                        finishstr = [NSString stringWithFormat:@"%@\n%@",finishstr,[content substringToIndex:range.location]];
                    }
                    //插入新生成的属性
                    finishstr = [NSString stringWithFormat:@"%@\n\n%@",finishstr,createMuchProperty()];
                    //添加当前位置的原内容
                    if (i == rangeArr.count - 1) {
                        //如果是最后一个位置
                        finishstr = [NSString stringWithFormat:@"%@\n\n%@",finishstr,[content substringWithRange:NSMakeRange(range.location, content.length-range.location)]];
                    } else {
                        //不是最后一个位置
                        NSString *nextStr = rangeArr[i+1];
                        NSRange nextRange = NSRangeFromString(nextStr);
                        finishstr = [NSString stringWithFormat:@"%@\n\n%@",finishstr,[content substringWithRange:NSMakeRange(range.location, nextRange.location-range.location)]];
                    }
                }
                if (finishstr.length > 0) {
                    [finishstr writeToFile:hPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
            }
        }
    }
}

#pragma mark 获取方法的返回值
void getMethodBackType(NSString *sourceCodeDir,NSArray<NSString *> *ignoreDirNames){
    NSFileManager *fm = [NSFileManager defaultManager];
    // 遍历源代码文件 h 与 m 配对，swift
//    NSMutableArray *preArr = [NSMutableArray new];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:sourceCodeDir error:nil];
    BOOL isDirectory;
    for (NSString *filePath in files) {
        @autoreleasepool {
            NSString *path = [sourceCodeDir stringByAppendingPathComponent:filePath];
            if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
                if (![ignoreDirNames containsObject:filePath]) {
                    getMethodBackType(path, ignoreDirNames);
                }
                continue;
            }
            //如果以m或mm结尾的
            if (([filePath hasSuffix:@".mm"] || [filePath hasSuffix:@".m"]) && ![filePath isEqualToString:@"main.m"]) {
//                NSLog(@"开始新的文件");
                NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];

                NSMutableArray *rangeArr = [NSMutableArray new];
                NSArray *searchArr = @[@"-(",@"- (",@"-  (",@"-   (",@"+(",@"+ (",@"+  (",@"+   ("];
                for (NSString *searchStr in searchArr) {
                    NSRange range = [content rangeOfString:searchStr];
                    while (range.location != NSNotFound || range.length != 0) {
//                        NSLog(@"匹配的位置是：%@",NSStringFromRange(range));
                        NSString *preStr = [content substringWithRange:NSMakeRange(range.location, 30)];
                        NSArray *preSpreaArr = [preStr componentsSeparatedByString:@")"];
                        if (preSpreaArr.count > 0) {
                            preStr = [NSString stringWithFormat:@"%@)",preSpreaArr.firstObject];
                        }
                        BOOL isContain =  NO;
                        for (NSString *forstr in methodPreArr) {
                            if ([forstr isEqualToString:preStr]) {
                                isContain = YES;
                            }
                        }
                        if (!isContain) {
                            [methodPreArr addObject:preStr];
                        }
                        
                        [rangeArr addObject:NSStringFromRange(range)];
                        NSUInteger hadSearchedRange = range.location + range.length;
                        NSRange resetRange = NSMakeRange(hadSearchedRange, content.length - hadSearchedRange);
                        range = [content rangeOfString:searchStr options:NSCaseInsensitiveSearch range:resetRange];
                    }
                }
            }
        }
    }
    
}

#pragma mark 向m文件中添加方法
void addMethodToMFile(NSString *sourceCodeDir,NSArray<NSString *> *ignoreDirNames) {
    NSFileManager *fm = [NSFileManager defaultManager];
    // 遍历源代码文件 h 与 m 配对，swift
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:sourceCodeDir error:nil];
    BOOL isDirectory;
    for (NSString *filePath in files) {
        @autoreleasepool {
            NSString *path = [sourceCodeDir stringByAppendingPathComponent:filePath];
            if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
                if (![ignoreDirNames containsObject:filePath]) {
                    addMethodToMFile(path, ignoreDirNames);
                }
                continue;
            }
            //如果以m或mm结尾的
            if (([filePath hasSuffix:@".mm"] || [filePath hasSuffix:@".m"]) && ![filePath isEqualToString:@"main.m"]) {
                
                NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
                NSLog(@"开始新的文件:%@====%lu",filePath,(unsigned long)content.length);
                /*
                 先找出implementat和end的位置，只有在这之间的方法才添加新的方法
                 */
                NSMutableArray *containArr = [NSMutableArray new];
                NSRange lastRange = NSMakeRange(0, content.length);
                BOOL isContinue =  YES;
                while (isContinue) {
                    NSRange range =  [content rangeOfString:@"@implementation" options:NSCaseInsensitiveSearch range:lastRange];
                    if (range.length == 0) {
                        isContinue =  NO;
                        continue;
                    }
                    if (range.location != NSNotFound || range.length != 0) {
                        [containArr addObject:NSStringFromRange(range)];
                        NSUInteger hadSearchedRange = range.location + range.length;
                        lastRange = NSMakeRange(hadSearchedRange, content.length - hadSearchedRange);
                        range = [content rangeOfString:@"@end" options:NSCaseInsensitiveSearch range:lastRange];
                        if (range.location != NSNotFound || range.length != 0) {
                            [containArr addObject:NSStringFromRange(range)];
                            NSUInteger hadSearchedRange = range.location + range.length;
                            lastRange = NSMakeRange(hadSearchedRange, content.length - hadSearchedRange);
                            if (hadSearchedRange >= content.length) {
                                isContinue =  NO;
                            }
                        } else {
                            isContinue = NO;
                        }
                    }
                }
              
                //确定方法所在的位置
                NSMutableArray *rangeArr = [NSMutableArray new];
                for (NSString *searchStr in allSearchArray) {
                    NSRange range = [content rangeOfString:searchStr];
                    while (range.location != NSNotFound || range.length != 0) {
                        //判断是否在implemenattio和end之间,只有在这个范围内的方法才添加进去
                        for (int i = 0; i < containArr.count-1; i += 2) {
                            NSString *firstR = containArr[i];
                            NSRange firstRan = NSRangeFromString(firstR);
                            NSString *secR = containArr[i + 1];
                            NSRange secRan = NSRangeFromString(secR);
                            if ((range.location < secRan.location) && (range.location > firstRan.location)) {
                                [rangeArr addObject:NSStringFromRange(range)];
                            }
                        }
                        
                        NSUInteger hadSearchedRange = range.location + range.length;
                        NSRange resetRange = NSMakeRange(hadSearchedRange, content.length - hadSearchedRange);
                        range = [content rangeOfString:searchStr options:NSCaseInsensitiveSearch range:resetRange];
                    }
                }
                //将范围按照从小到大的顺序排序
                if (rangeArr.count != 0) {
                    if (rangeArr.count == 1) {
                        
                    } else {
                        for (int i = 0; i < rangeArr.count-1; i ++) {
                            BOOL isEnd = NO;
                            for (int j = 0; j < rangeArr.count - i - 1; j ++) {
                                NSString *secStr = rangeArr[j];
                                NSRange secRan = NSRangeFromString(secStr);
                                
                                NSString *thirStr = rangeArr[j+1];
                                NSRange thieRan = NSRangeFromString(thirStr);
                                if (secRan.location > thieRan.location) {
                                    isEnd = YES;
                                    [rangeArr exchangeObjectAtIndex:j withObjectAtIndex:j+1];
                                }
                            }
                            if (!isEnd) {
                                break;
                            }
                        }
                    }
                 
                    
                    NSString *finishstr = @"";
                    for (int i = 0; i < rangeArr.count; i ++) {
                        NSString *rangeStr = rangeArr[i];
                        NSRange range = NSRangeFromString(rangeStr);
                        //先插入当前位置之前的内容
                        if (i == 0) {
                            finishstr = [NSString stringWithFormat:@"%@",[content substringToIndex:range.location]];
                        }
                        //插入新生成的方法
                        finishstr = [NSString stringWithFormat:@"%@\n\n%@",finishstr,createSingleMethod()];
                        //添加当前位置的原方法
                        if (i == rangeArr.count - 1) {
                            //如果是最后一个位置
                            finishstr = [NSString stringWithFormat:@"%@\n\n%@",finishstr,[content substringWithRange:NSMakeRange(range.location, content.length-range.location)]];
                        } else {
                            //不是最后一个位置
                            NSString *nextStr = rangeArr[i+1];
                            NSRange nextRange = NSRangeFromString(nextStr);
                            finishstr = [NSString stringWithFormat:@"%@\n\n%@",finishstr,[content substringWithRange:NSMakeRange(range.location, nextRange.location-range.location)]];
                        }
                    }
                    if (finishstr.length > 0) {
                        [finishstr writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    }
                    
                }
               
            }
        }
    }
}


#pragma mark 生成新的.h.m文件
void createNewFile(NSString *outDirectory) {
    //确定类名的长度及类名
    int clasNameLen = arc4random() % 20 + 10;
    NSString *clasName = @"TTR";
    for (int i = 0 ; i < clasNameLen; i ++) {
        clasName = [NSString stringWithFormat:@"%@%@",clasName,chartArray[arc4random() % chartArray.count]];
    }
    
    //hm文件名
    NSString *HFileName = [NSString stringWithFormat:@"%@.h",clasName];
    NSString *MFileName = [NSString stringWithFormat:@"%@.m",clasName];
    //Hm文件内容
    NSString *HContent = [NSString stringWithFormat:@"#import <Foundation/Foundation.h>\n\n#import <UIKit/UIKit.h>\n\n@interface %@: NSObject",clasName];
    NSString *MContent = [NSString stringWithFormat:@"#import \"%@\" \n\n@implementation %@: NSObject",HFileName,clasName];
    //h文件添加属性
    HContent = [NSString stringWithFormat:@"%@\n\n%@",HContent,createMuchProperty()];
    //h文件添加方法
    NSMutableArray *methodArr = [[NSMutableArray alloc] init];
    int methodNum =  arc4random() % 10 + 10;
    NSString *methodStr = @"";
    for (int i = 0 ; i < methodNum; i ++) {
        NSString *method = createMethod();
        [methodArr addObject:method];
        methodStr = [NSString stringWithFormat:@"%@\n%@",methodStr,method];
    }
    HContent = [NSString stringWithFormat:@"%@\n\n%@",HContent,methodStr];
    
    //m文件添加方法
    for (NSString *methodString in methodArr) {
        NSString * subMethod = [methodString stringByReplacingOccurrencesOfString:@";" withString:@"{\n"];
        //添加方法的内容
        int methodNum = arc4random() % 10 + 10;
        for (int i = 0; i < methodNum; i ++) {
            NSString *str = clasStr();
            subMethod = [NSString stringWithFormat:@"%@%@\n",subMethod,str];
        }
        subMethod = [NSString stringWithFormat:@"%@\n\n}",subMethod];
        MContent = [NSString stringWithFormat:@"%@\n\n%@",MContent,subMethod];
    }
    
    
    HContent = [NSString stringWithFormat:@"%@\n\n@end",HContent];
    MContent = [NSString stringWithFormat:@"%@\n\n@end",MContent];
    
    //内容写入文件
    [HContent writeToFile:[outDirectory stringByAppendingPathComponent:HFileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [MContent writeToFile:[outDirectory stringByAppendingPathComponent:MFileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"生成的文件名称是：%@=======%@",HFileName,MFileName);
}

NSString * clasStr(void) {
    
    //确定返回类型是哪一个类
    int clasRandomNum =  arc4random() % backArray.count;
    NSString *clasString = [NSString stringWithFormat:@"%@",backArray[clasRandomNum]];
    
    //确定类名的长度及类名
    int clasNameLen = arc4random() % backArray.count + 5;
    NSString *clasName = @"HCL";
    for (int i = 0 ; i < clasNameLen; i ++) {
        clasName = [NSString stringWithFormat:@"%@%@",clasName,chartArray[arc4random() % chartArray.count]];
    }
    
    //初始化
    if ([clasString isEqualToString:@"NSArray"]) {
        NSString *initStr = @"@[";
        int arrLen = arc4random() % chartArray.count + 10;
        for (int i = 0; i < arrLen; i ++) {
            initStr = [NSString stringWithFormat:@"%@@\"%@\",",initStr,chartArray[arc4random() % chartArray.count]];
        }
        initStr = [NSString stringWithFormat:@"%@]",initStr];
        clasString = [NSString stringWithFormat:@"    %@ *%@ = %@;",clasString,clasName,initStr];
        
        NSString *logStr = [NSString stringWithFormat:@"%@.count",clasName];
        logStr = [NSString stringWithFormat:@"NSLog(@\"^?\",(unsigned long)%@);",logStr];
        logStr = [logStr stringByReplacingOccurrencesOfString:@"^" withString:@"%"];
        logStr = [logStr stringByReplacingOccurrencesOfString:@"?" withString:@"lu"];
        
        clasString = [NSString stringWithFormat:@"%@\n    %@",clasString,logStr];
        
    } else if ([clasString isEqualToString:@"NSString"]) {
        NSString *initStr = @"@\"";
        int arrLen = arc4random() % chartArray.count + 20;
        for (int i = 0; i < arrLen; i ++) {
            initStr = [NSString stringWithFormat:@"%@%@",initStr,chartArray[arc4random() % chartArray.count]];
        }
        initStr = [NSString stringWithFormat:@"%@\"",initStr];
        clasString = [NSString stringWithFormat:@"    %@ *%@ = %@;",clasString,clasName,initStr];
        
        NSString *logStr = [NSString stringWithFormat:@"%@.length",clasName];
        logStr = [NSString stringWithFormat:@"NSLog(@\"^?\",(unsigned long)%@);",logStr];
        logStr = [logStr stringByReplacingOccurrencesOfString:@"^" withString:@"%"];
        logStr = [logStr stringByReplacingOccurrencesOfString:@"?" withString:@"lu"];
        
        NSString *subStr = [NSString stringWithFormat:@"[%@ isEqualToString:@\"%@\"];",clasName,clasName];
        
        clasString = [NSString stringWithFormat:@"%@\n    %@\n    %@",clasString,logStr,subStr];
    } else if ([clasString isEqualToString:@"NSDictionary"]) {
        NSString *initStr = @"@{";
        int arrLen = arc4random() % chartArray.count + 20;
        for (int i = 0; i < arrLen; i ++) {
            NSString *keyStr = [NSString stringWithFormat:@"@\"%@\":",chartArray[arc4random() % chartArray.count]];
            if ([initStr containsString:keyStr]) {
                continue;
            }
            initStr = [NSString stringWithFormat:@"%@%@@\"%@\",",initStr,keyStr,chartArray[arc4random() % chartArray.count]];
        }
        initStr = [NSString stringWithFormat:@"%@}",initStr];
        clasString = [NSString stringWithFormat:@"    %@ *%@ = %@;",clasString,clasName,initStr];
        
        NSString *logStr = [NSString stringWithFormat:@"%@.count",clasName];
        logStr = [NSString stringWithFormat:@"NSLog(@\"^?\",(unsigned long)%@);",logStr];
        logStr = [logStr stringByReplacingOccurrencesOfString:@"^" withString:@"%"];
        logStr = [logStr stringByReplacingOccurrencesOfString:@"?" withString:@"lu"];
        
        clasString = [NSString stringWithFormat:@"%@\n    %@",clasString,logStr];
    } else {
        clasString = [NSString stringWithFormat:@"    %@ *%@ = [[%@ alloc] init];",clasString,clasName,clasString];
    }
    return clasString;
}

#pragma mark 直接在m文件创建一个新方法
NSString * createSingleMethod(void) {

    int randomNum = arc4random() % chartArray.count + 20;
    NSString *str = @"HCL";
    for (int i  = 0; i < randomNum; i ++) {
        str = [NSString stringWithFormat:@"%@%@",str,chartArray[arc4random()%chartArray.count]];
    }
    NSString *methodStr = [NSString stringWithFormat:@"- (void)%@ {\n\n",str];
    int methodNum = arc4random() % 10 + 5;
    for (int i = 0; i < methodNum; i ++) {
        NSString *str = clasStr();
        methodStr = [NSString stringWithFormat:@"%@%@\n",methodStr,str];
    }
    methodStr = [NSString stringWithFormat:@"%@\n}",methodStr];
    return methodStr;
}

#pragma mark h文件创建单个方法
NSString * createMethod(void) {

    int randomNum = arc4random() % chartArray.count + 20;
    NSString *str = @"HCL";
    for (int i  = 0; i < randomNum; i ++) {
        str = [NSString stringWithFormat:@"%@%@",str,chartArray[arc4random()%chartArray.count]];
    }
    
    NSString *methodStr = [NSString stringWithFormat:@"- (void)%@;",str];
    return methodStr;
}

#pragma mark 生成多个属性
NSString * createMuchProperty(void)  {
    int arcNum = arc4random() % 20 + 10;
    NSString *str = @"";
    for (int i = 0; i < arcNum; i ++) {
        NSString *string = createSingleProperty();
        str = [NSString stringWithFormat:@"%@\n%@",str,string];
    }
    return str;
}

#pragma mark 单独创建一个属性
NSString * createSingleProperty(void) {
    NSString *backStr = @"";
    
    //属性名称
    //确定类名的长度及类名
    int clasNameLen = arc4random() % 20 + 5;
    NSString *clasName = @"HCL";
    for (int i = 0 ; i < clasNameLen; i ++) {
        clasName = [NSString stringWithFormat:@"%@%@",clasName,chartArray[arc4random() % chartArray.count]];
    }
    
    
    NSString *clasStr = propertyArray[arc4random() % propertyArray.count];
    if ([clasStr isEqualToString:@"int"] || [clasStr isEqualToString:@"BOOL"] || [clasStr isEqualToString:@"NSInteger"]) {
        backStr = [NSString stringWithFormat:@"@property(assign,nonatomic) %@ %@;",clasStr,clasName];
    } else {
        backStr = [NSString stringWithFormat:@"@property(strong,nonatomic) %@ *%@;",clasStr,clasName];
    }
    return backStr;
}

#pragma mark - 生成垃圾代码

void recursiveDirectory(NSString *directory, NSArray<NSString *> *ignoreDirNames, void(^handleMFile)(NSString *mFilePath), void(^handleSwiftFile)(NSString *swiftFilePath)) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:directory error:nil];
    BOOL isDirectory;
    for (NSString *filePath in files) {
        NSString *path = [directory stringByAppendingPathComponent:filePath];
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            if (![ignoreDirNames containsObject:filePath]) {
                recursiveDirectory(path, nil, handleMFile, handleSwiftFile);
            }
            continue;
        }
        NSString *fileName = filePath.lastPathComponent;
        if ([fileName hasSuffix:@".h"]) {
            fileName = [fileName stringByDeletingPathExtension];
            
            NSString *mFileName = [fileName stringByAppendingPathExtension:@"m"];
            if ([files containsObject:mFileName]) {
                handleMFile([directory stringByAppendingPathComponent:mFileName]);
            }
        } else if ([fileName hasSuffix:@".swift"]) {
            handleSwiftFile([directory stringByAppendingPathComponent:fileName]);
        }
    }
}

NSString * getImportString(NSString *hFileContent, NSString *mFileContent) {
    NSMutableString *ret = [NSMutableString string];
    
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^ *[@#]import *.+" options:NSRegularExpressionAnchorsMatchLines|NSRegularExpressionUseUnicodeWordBoundaries error:nil];
    
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:hFileContent options:0 range:NSMakeRange(0, hFileContent.length)];
    [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *importRow = [hFileContent substringWithRange:[obj rangeAtIndex:0]];
        [ret appendString:importRow];
        [ret appendString:@"\n"];
    }];
    
    matches = [expression matchesInString:mFileContent options:0 range:NSMakeRange(0, mFileContent.length)];
    [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *importRow = [mFileContent substringWithRange:[obj rangeAtIndex:0]];
        [ret appendString:importRow];
        [ret appendString:@"\n"];
    }];
    
    return ret;
}

static NSString *const kHClassFileTemplate = @"\
%@\n\
@interface %@ (%@)\n\
%@\n\
@end\n";
static NSString *const kMClassFileTemplate = @"\
#import \"%@+%@.h\"\n\
@implementation %@ (%@)\n\
%@\n\
@end\n";
static NSString *const kHNewClassFileTemplate = @"\
#import <Foundation/Foundation.h>\n\
@interface %@: NSObject\n\
%@\n\
@end\n";
static NSString *const kMNewClassFileTemplate = @"\
#import \"%@.h\"\n\
@implementation %@\n\
%@\n\
@end\n";
void generateSpamCodeFile(NSString *outDirectory, NSString *mFilePath, GSCSourceType type, NSMutableString *categoryCallImportString, NSMutableString *categoryCallFuncString, NSMutableString *newClassCallImportString, NSMutableString *newClassCallFuncString) {
    NSString *mFileContent = [NSString stringWithContentsOfFile:mFilePath encoding:NSUTF8StringEncoding error:nil];
    NSString *regexStr;
    switch (type) {
        case GSCSourceTypeClass:
            regexStr = @" *@implementation +(\\w+)[^(]*\\n(?:.|\\n)+?@end";
            break;
        case GSCSourceTypeCategory:
            regexStr = @" *@implementation *(\\w+) *\\((\\w+)\\)(?:.|\\n)+?@end";
            break;
    }
    
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regexStr options:NSRegularExpressionUseUnicodeWordBoundaries error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:mFileContent options:0 range:NSMakeRange(0, mFileContent.length)];
    if (matches.count <= 0) return;
    
    NSString *hFilePath = [mFilePath.stringByDeletingPathExtension stringByAppendingPathExtension:@"h"];
    NSString *hFileContent = [NSString stringWithContentsOfFile:hFilePath encoding:NSUTF8StringEncoding error:nil];
    
    // 准备要引入的文件
    NSString *fileImportStrings = getImportString(hFileContent, mFileContent);
    
    [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull impResult, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *className = [mFileContent substringWithRange:[impResult rangeAtIndex:1]];
        NSString *categoryName = nil;
        NSString *newClassName = [NSString stringWithFormat:@"%@%@%@", gOutParameterName, className, randomLetter()];
        if (impResult.numberOfRanges >= 3) {
            categoryName = [mFileContent substringWithRange:[impResult rangeAtIndex:2]];
        }
        
        if (type == GSCSourceTypeClass) {
            // 如果该类型没有公开，只在 .m 文件中使用，则不处理
            NSString *regexStr = [NSString stringWithFormat:@"\\b%@\\b", className];
            NSRange range = [hFileContent rangeOfString:regexStr options:NSRegularExpressionSearch];
            if (range.location == NSNotFound) {
                return;
            }
        }

        // 查找方法
        NSString *implementation = [mFileContent substringWithRange:impResult.range];
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^ *([-+])[^)]+\\)([^;{]+)" options:NSRegularExpressionAnchorsMatchLines|NSRegularExpressionUseUnicodeWordBoundaries error:nil];
        NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:implementation options:0 range:NSMakeRange(0, implementation.length)];
        if (matches.count <= 0) return;
        
        // 新类 h m 垃圾文件内容
        NSMutableString *hNewClassFileMethodsString = [NSMutableString string];
        NSMutableString *mNewClassFileMethodsString = [NSMutableString string];
        
        // 生成 h m 垃圾文件内容
        NSMutableString *hFileMethodsString = [NSMutableString string];
        NSMutableString *mFileMethodsString = [NSMutableString string];
        [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull matche, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *symbol = @"+";//[implementation substringWithRange:[matche rangeAtIndex:1]];
            NSString *methodName = [[implementation substringWithRange:[matche rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *newClassMethodName = nil;
            NSString *methodCallName = nil;
            NSString *newClassMethodCallName = nil;
            if ([methodName containsString:@":"]) {
                // 去掉参数，生成无参数的新名称
                NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"\\b([\\w]+) *:" options:0 error:nil];
                NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:methodName options:0 range:NSMakeRange(0, methodName.length)];
                if (matches.count > 0) {
                    NSMutableString *newMethodName = [NSMutableString string];
                    NSMutableString *newClassNewMethodName = [NSMutableString string];
                    [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull matche, NSUInteger idx, BOOL * _Nonnull stop) {
                        NSString *str = [methodName substringWithRange:[matche rangeAtIndex:1]];
                        [newMethodName appendString:(newMethodName.length > 0 ? str.capitalizedString : str)];
                        [newClassNewMethodName appendFormat:@"%@%@", randomLetter(), str.capitalizedString];
                    }];
                    methodCallName = [NSString stringWithFormat:@"%@%@", newMethodName, gOutParameterName.capitalizedString];
                    [newMethodName appendFormat:@"%@:(NSInteger)%@", gOutParameterName.capitalizedString, gOutParameterName];
                    methodName = newMethodName;
                    
                    newClassMethodCallName = [NSString stringWithFormat:@"%@", newClassNewMethodName];
                    newClassMethodName = [NSString stringWithFormat:@"%@:(NSInteger)%@", newClassMethodCallName, gOutParameterName];
                } else {
                    methodName = [methodName stringByAppendingFormat:@" %@:(NSInteger)%@", gOutParameterName, gOutParameterName];
                }
            } else {
                newClassMethodCallName = [NSString stringWithFormat:@"%@%@", randomLetter(), methodName];
                newClassMethodName = [NSString stringWithFormat:@"%@:(NSInteger)%@", newClassMethodCallName, gOutParameterName];
                
                methodCallName = [NSString stringWithFormat:@"%@%@", methodName, gOutParameterName.capitalizedString];
                methodName = [methodName stringByAppendingFormat:@"%@:(NSInteger)%@", gOutParameterName.capitalizedString, gOutParameterName];
            }
            
            [hFileMethodsString appendFormat:@"%@ (BOOL)%@;\n", symbol, methodName];
            
            [mFileMethodsString appendFormat:@"%@ (BOOL)%@ {\n", symbol, methodName];
            [mFileMethodsString appendFormat:@"    return %@ %% %u == 0;\n", gOutParameterName, arc4random_uniform(50) + 1];
            [mFileMethodsString appendString:@"}\n"];
            
            if (methodCallName.length > 0) {
                if (gSpamCodeFuncationCallName && categoryCallFuncString.length <= 0) {
                    [categoryCallFuncString appendFormat:@"static inline NSInteger %@() {\nNSInteger ret = 0;\n", gSpamCodeFuncationCallName];
                }
                [categoryCallFuncString appendFormat:@"ret += [%@ %@:%u] ? 1 : 0;\n", className, methodCallName, arc4random_uniform(100)];
            }
            
            
            if (newClassMethodName.length > 0) {
                [hNewClassFileMethodsString appendFormat:@"%@ (BOOL)%@;\n", symbol, newClassMethodName];
                
                [mNewClassFileMethodsString appendFormat:@"%@ (BOOL)%@ {\n", symbol, newClassMethodName];
                [mNewClassFileMethodsString appendFormat:@"    return %@ %% %u == 0;\n", gOutParameterName, arc4random_uniform(50) + 1];
                [mNewClassFileMethodsString appendString:@"}\n"];
            }
            
            if (newClassMethodCallName.length > 0) {
                if (gNewClassFuncationCallName && newClassCallFuncString.length <= 0) {
                    [newClassCallFuncString appendFormat:@"static inline NSInteger %@() {\nNSInteger ret = 0;\n", gNewClassFuncationCallName];
                }
                [newClassCallFuncString appendFormat:@"ret += [%@ %@:%u] ? 1 : 0;\n", newClassName, newClassMethodCallName, arc4random_uniform(100)];
            }
        }];
        
        NSString *newCategoryName;
        switch (type) {
            case GSCSourceTypeClass:
                newCategoryName = gOutParameterName.capitalizedString;
                break;
            case GSCSourceTypeCategory:
                newCategoryName = [NSString stringWithFormat:@"%@%@", categoryName, gOutParameterName.capitalizedString];
                break;
        }
        
        // category m
        NSString *fileName = [NSString stringWithFormat:@"%@+%@.m", className, newCategoryName];
        NSString *fileContent = [NSString stringWithFormat:kMClassFileTemplate, className, newCategoryName, className, newCategoryName, mFileMethodsString];
        [fileContent writeToFile:[outDirectory stringByAppendingPathComponent:fileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        // category h
        fileName = [NSString stringWithFormat:@"%@+%@.h", className, newCategoryName];
        fileContent = [NSString stringWithFormat:kHClassFileTemplate, fileImportStrings, className, newCategoryName, hFileMethodsString];
        [fileContent writeToFile:[outDirectory stringByAppendingPathComponent:fileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        [categoryCallImportString appendFormat:@"#import \"%@\"\n", fileName];
        
        // new class m
        NSString *newOutDirectory = [outDirectory stringByAppendingPathComponent:kNewClassDirName];
        fileName = [NSString stringWithFormat:@"%@.m", newClassName];
        fileContent = [NSString stringWithFormat:kMNewClassFileTemplate, newClassName, newClassName, mNewClassFileMethodsString];
        [fileContent writeToFile:[newOutDirectory stringByAppendingPathComponent:fileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        // new class h
        fileName = [NSString stringWithFormat:@"%@.h", newClassName];
        fileContent = [NSString stringWithFormat:kHNewClassFileTemplate, newClassName, hNewClassFileMethodsString];
        [fileContent writeToFile:[newOutDirectory stringByAppendingPathComponent:fileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        [newClassCallImportString appendFormat:@"#import \"%@\"\n", fileName];
    }];
}

static NSString *const kSwiftFileTemplate = @"\
%@\n\
extension %@ {\n%@\
}\n";
static NSString *const kSwiftMethodTemplate = @"\
    func %@%@(_ %@: String%@) {\n\
        print(%@)\n\
    }\n";
void generateSwiftSpamCodeFile(NSString *outDirectory, NSString *swiftFilePath) {
    NSString *swiftFileContent = [NSString stringWithContentsOfFile:swiftFilePath encoding:NSUTF8StringEncoding error:nil];
    
    // 查找 class 声明
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@" *(class|struct) +(\\w+)[^{]+" options:NSRegularExpressionUseUnicodeWordBoundaries error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:swiftFileContent options:0 range:NSMakeRange(0, swiftFileContent.length)];
    if (matches.count <= 0) return;
    
    NSString *fileImportStrings = getSwiftImportString(swiftFileContent);
    __block NSInteger braceEndIndex = 0;
    [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull classResult, NSUInteger idx, BOOL * _Nonnull stop) {
        // 已经处理到该 range 后面去了，过掉
        NSInteger matchEndIndex = classResult.range.location + classResult.range.length;
        if (matchEndIndex < braceEndIndex) return;
        // 是 class 方法，过掉
        NSString *fullMatchString = [swiftFileContent substringWithRange:classResult.range];
        if ([fullMatchString containsString:@"("]) return;
        
        NSRange braceRange = getOutermostCurlyBraceRange(swiftFileContent, '{', '}', matchEndIndex);
        braceEndIndex = braceRange.location + braceRange.length;
        
        // 查找方法
        NSString *classContent = [swiftFileContent substringWithRange:braceRange];
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"func +([^(]+)\\([^{]+" options:NSRegularExpressionUseUnicodeWordBoundaries error:nil];
        NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:classContent options:0 range:NSMakeRange(0, classContent.length)];
        if (matches.count <= 0) return;
        
        NSMutableString *methodsString = [NSMutableString string];
        [matches enumerateObjectsUsingBlock:^(NSTextCheckingResult * _Nonnull funcResult, NSUInteger idx, BOOL * _Nonnull stop) {
            NSRange funcNameRange = [funcResult rangeAtIndex:1];
            NSString *funcName = [classContent substringWithRange:funcNameRange];
            NSRange oldParameterRange = getOutermostCurlyBraceRange(classContent, '(', ')', funcNameRange.location + funcNameRange.length);
            NSString *oldParameterName = [classContent substringWithRange:oldParameterRange];
            oldParameterName = [oldParameterName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (oldParameterName.length > 0) {
                oldParameterName = [@", " stringByAppendingString:oldParameterName];
            }
            if (![funcName containsString:@"<"] && ![funcName containsString:@">"]) {
                funcName = [NSString stringWithFormat:@"%@%@", funcName, randomString(5)];
                [methodsString appendFormat:kSwiftMethodTemplate, funcName, gOutParameterName.capitalizedString, gOutParameterName, oldParameterName, gOutParameterName];
            } else {
                NSLog(@"string contains `[` or `]` bla! funcName: %@", funcName);
            }
        }];
        if (methodsString.length <= 0) return;
        
        NSString *className = [swiftFileContent substringWithRange:[classResult rangeAtIndex:2]];
        
        NSString *fileName = [NSString stringWithFormat:@"%@%@Ext.swift", className, gOutParameterName.capitalizedString];
        NSString *filePath = [outDirectory stringByAppendingPathComponent:fileName];
        NSString *fileContent = @"";
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            fileContent = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        }
        fileContent = [fileContent stringByAppendingFormat:kSwiftFileTemplate, fileImportStrings, className, methodsString];
        [fileContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }];
}

#pragma mark - 处理 Xcassets 中的图片文件

void handleXcassetsFiles(NSString *directory) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:directory error:nil];
    BOOL isDirectory;
    for (NSString *fileName in files) {
        NSString *filePath = [directory stringByAppendingPathComponent:fileName];
        if ([fm fileExistsAtPath:filePath isDirectory:&isDirectory] && isDirectory) {
            handleXcassetsFiles(filePath);
            continue;
        }
        if (![fileName isEqualToString:@"Contents.json"]) continue;
        NSString *contentsDirectoryName = filePath.stringByDeletingLastPathComponent.lastPathComponent;
        if (![contentsDirectoryName hasSuffix:@".imageset"]) continue;
        
        NSString *fileContent = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        if (!fileContent) continue;
        
        NSMutableArray<NSString *> *processedImageFileNameArray = @[].mutableCopy;
        static NSString * const regexStr = @"\"filename\" *: *\"(.*)?\"";
        NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regexStr options:NSRegularExpressionUseUnicodeWordBoundaries error:nil];
        NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
        while (matches.count > 0) {
            NSInteger i = 0;
            NSString *imageFileName = nil;
            do {
                if (i >= matches.count) {
                    i = -1;
                    break;
                }
                imageFileName = [fileContent substringWithRange:[matches[i] rangeAtIndex:1]];
                i++;
            } while ([processedImageFileNameArray containsObject:imageFileName]);
            if (i < 0) break;
            
            NSString *imageFilePath = [filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:imageFileName];
            if ([fm fileExistsAtPath:imageFilePath]) {
                NSString *newImageFileName = [randomString(10) stringByAppendingPathExtension:imageFileName.pathExtension];
                NSString *newImageFilePath = [filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:newImageFileName];
                while ([fm fileExistsAtPath:newImageFileName]) {
                    newImageFileName = [randomString(10) stringByAppendingPathExtension:imageFileName.pathExtension];
                    newImageFilePath = [filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:newImageFileName];
                }
                
                renameFile(imageFilePath, newImageFilePath);
                
                fileContent = [fileContent stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"\"%@\"", imageFileName]
                                                                     withString:[NSString stringWithFormat:@"\"%@\"", newImageFileName]];
                [fileContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                
                [processedImageFileNameArray addObject:newImageFileName];
            } else {
                [processedImageFileNameArray addObject:imageFileName];
            }
            
            matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
        }
    }
}

#pragma mark - 删除注释

void deleteComments(NSString *directory, NSArray<NSString *> *ignoreDirNames) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:directory error:nil];
    BOOL isDirectory;
    for (NSString *fileName in files) {
        if ([ignoreDirNames containsObject:fileName]) continue;
        NSString *filePath = [directory stringByAppendingPathComponent:fileName];
        if ([fm fileExistsAtPath:filePath isDirectory:&isDirectory] && isDirectory) {
            deleteComments(filePath, ignoreDirNames);
            continue;
        }
        if (![fileName hasSuffix:@".h"] && ![fileName hasSuffix:@".m"] && ![fileName hasSuffix:@".mm"] && ![fileName hasSuffix:@".swift"]) continue;
        NSMutableString *fileContent = [NSMutableString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        regularReplacement(fileContent, @"([^:/])//.*",             @"\\1");
        regularReplacement(fileContent, @"^//.*",                   @"");
        regularReplacement(fileContent, @"/\\*{1,2}[\\s\\S]*?\\*/", @"");
        regularReplacement(fileContent, @"^\\s*\\n",                @"");
        [fileContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - 修改工程名

void resetEntitlementsFileName(NSString *projectPbxprojFilePath, NSString *oldName, NSString *newName) {
    NSString *rootPath = projectPbxprojFilePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
    NSMutableString *fileContent = [NSMutableString stringWithContentsOfFile:projectPbxprojFilePath encoding:NSUTF8StringEncoding error:nil];
    
    NSString *regularExpression = @"CODE_SIGN_ENTITLEMENTS = \"?([^\";]+)";
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regularExpression options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
    [matches enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *entitlementsPath = [fileContent substringWithRange:[obj rangeAtIndex:1]];
        NSString *entitlementsName = entitlementsPath.lastPathComponent.stringByDeletingPathExtension;
        if (![entitlementsName isEqualToString:oldName]) return;
        entitlementsPath = [rootPath stringByAppendingPathComponent:entitlementsPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:entitlementsPath]) return;
        NSString *newPath = [entitlementsPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:[newName stringByAppendingPathExtension:@"entitlements"]];
        renameFile(entitlementsPath, newPath);
    }];
}

void resetBridgingHeaderFileName(NSString *projectPbxprojFilePath, NSString *oldName, NSString *newName) {
    NSString *rootPath = projectPbxprojFilePath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
    NSMutableString *fileContent = [NSMutableString stringWithContentsOfFile:projectPbxprojFilePath encoding:NSUTF8StringEncoding error:nil];
    
    NSString *regularExpression = @"SWIFT_OBJC_BRIDGING_HEADER = \"?([^\";]+)";
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regularExpression options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
    [matches enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *entitlementsPath = [fileContent substringWithRange:[obj rangeAtIndex:1]];
        NSString *entitlementsName = entitlementsPath.lastPathComponent.stringByDeletingPathExtension;
        if (![entitlementsName isEqualToString:oldName]) return;
        entitlementsPath = [rootPath stringByAppendingPathComponent:entitlementsPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:entitlementsPath]) return;
        NSString *newPath = [entitlementsPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:[newName stringByAppendingPathExtension:@"h"]];
        renameFile(entitlementsPath, newPath);
    }];
}

void replacePodfileContent(NSString *filePath, NSString *oldString, NSString *newString) {
    NSMutableString *fileContent = [NSMutableString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    
    NSString *regularExpression = [NSString stringWithFormat:@"target +'%@", oldString];
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regularExpression options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
    [matches enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [fileContent replaceCharactersInRange:obj.range withString:[NSString stringWithFormat:@"target '%@", newString]];
    }];
    
    regularExpression = [NSString stringWithFormat:@"project +'%@.", oldString];
    expression = [NSRegularExpression regularExpressionWithPattern:regularExpression options:0 error:nil];
    matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
    [matches enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [fileContent replaceCharactersInRange:obj.range withString:[NSString stringWithFormat:@"project '%@.", newString]];
    }];
    
    [fileContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

void replaceProjectFileContent(NSString *filePath, NSString *oldString, NSString *newString) {
    NSMutableString *fileContent = [NSMutableString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    
    NSString *regularExpression = [NSString stringWithFormat:@"\\b%@\\b", oldString];
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:regularExpression options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [expression matchesInString:fileContent options:0 range:NSMakeRange(0, fileContent.length)];
    [matches enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSTextCheckingResult * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [fileContent replaceCharactersInRange:obj.range withString:newString];
    }];
    
    [fileContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

void modifyFilesClassName(NSString *sourceCodeDir, NSString *oldClassName, NSString *newClassName);

#pragma mark 修改工程名称
void modifyProjectName(NSString *projectDir, NSString *oldName, NSString *newName) {
    
    NSLog(@"开始修改工程：%@===%@===%@",projectDir,oldName,newName);
    
    NSString *sourceCodeDirPath = [projectDir stringByAppendingPathComponent:oldName];
    NSString *xcodeprojFilePath = [sourceCodeDirPath stringByAppendingPathExtension:@"xcodeproj"];
    NSString *xcworkspaceFilePath = [sourceCodeDirPath stringByAppendingPathExtension:@"xcworkspace"];
    NSLog(@"开始修改工程1111：%@===%@===%@",sourceCodeDirPath,xcodeprojFilePath,xcworkspaceFilePath);
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory;
    
    // old-Swift.h > new-Swift.h
    modifyFilesClassName(projectDir, [oldName stringByAppendingString:@"-Swift.h"], [newName stringByAppendingString:@"-Swift.h"]);
    
    // 改 Podfile 中的工程名
    NSString *podfilePath = [projectDir stringByAppendingPathComponent:@"Podfile"];
    if ([fm fileExistsAtPath:podfilePath isDirectory:&isDirectory] && !isDirectory) {
        replacePodfileContent(podfilePath, oldName, newName);
    }
    
    // 改工程文件内容
    if ([fm fileExistsAtPath:xcodeprojFilePath isDirectory:&isDirectory] && isDirectory) {
        // 替换 project.pbxproj 文件内容
        NSString *projectPbxprojFilePath = [xcodeprojFilePath stringByAppendingPathComponent:@"project.pbxproj"];
        if ([fm fileExistsAtPath:projectPbxprojFilePath]) {
            resetBridgingHeaderFileName(projectPbxprojFilePath, [oldName stringByAppendingString:@"-Bridging-Header"], [newName stringByAppendingString:@"-Bridging-Header"]);
            resetEntitlementsFileName(projectPbxprojFilePath, oldName, newName);
            replaceProjectFileContent(projectPbxprojFilePath, oldName, newName);
        }
        // 替换 project.xcworkspace/contents.xcworkspacedata 文件内容
        NSString *contentsXcworkspacedataFilePath = [xcodeprojFilePath stringByAppendingPathComponent:@"project.xcworkspace/contents.xcworkspacedata"];
        if ([fm fileExistsAtPath:contentsXcworkspacedataFilePath]) {
            replaceProjectFileContent(contentsXcworkspacedataFilePath, oldName, newName);
        }
        // xcuserdata 本地用户文件
        NSString *xcuserdataFilePath = [xcodeprojFilePath stringByAppendingPathComponent:@"xcuserdata"];
        if ([fm fileExistsAtPath:xcuserdataFilePath]) {
            [fm removeItemAtPath:xcuserdataFilePath error:nil];
        }
        // 改名工程文件
        renameFile(xcodeprojFilePath, [[projectDir stringByAppendingPathComponent:newName] stringByAppendingPathExtension:@"xcodeproj"]);
    }
    
    // 改工程组文件内容
    if ([fm fileExistsAtPath:xcworkspaceFilePath isDirectory:&isDirectory] && isDirectory) {
        // 替换 contents.xcworkspacedata 文件内容
        NSString *contentsXcworkspacedataFilePath = [xcworkspaceFilePath stringByAppendingPathComponent:@"contents.xcworkspacedata"];
        if ([fm fileExistsAtPath:contentsXcworkspacedataFilePath]) {
            replaceProjectFileContent(contentsXcworkspacedataFilePath, oldName, newName);
        }
        // xcuserdata 本地用户文件
        NSString *xcuserdataFilePath = [xcworkspaceFilePath stringByAppendingPathComponent:@"xcuserdata"];
        if ([fm fileExistsAtPath:xcuserdataFilePath]) {
            [fm removeItemAtPath:xcuserdataFilePath error:nil];
        }
        // 改名工程文件
        renameFile(xcworkspaceFilePath, [[projectDir stringByAppendingPathComponent:newName] stringByAppendingPathExtension:@"xcworkspace"]);
    }
    
    // 改源代码文件夹名称
    if ([fm fileExistsAtPath:sourceCodeDirPath isDirectory:&isDirectory] && isDirectory) {
        NSString *str = [projectDir stringByAppendingPathComponent:newName];
        NSLog(@"修改文件名称啦啦啦啦：%@=======%@",str,sourceCodeDirPath);
        renameFile(sourceCodeDirPath, str);
    }
    
    // 改源文件夹名称
    if ([fm fileExistsAtPath:projectDir isDirectory:&isDirectory] && isDirectory) {
        NSString *str = [projectDir.stringByDeletingLastPathComponent stringByAppendingPathComponent:newName];
        NSLog(@"修改文件名称啦啦啦啦11111：%@=======%@",str,projectDir);
        renameFile(projectDir, str);
    }
}




void modifyFilesClassName(NSString *sourceCodeDir, NSString *oldClassName, NSString *newClassName) {
    // 文件内容 Const > DDConst (h,m,swift,xib,storyboard)
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:sourceCodeDir error:nil];
    BOOL isDirectory;
//    NSLog(@"当前文件夹下的文件是：%@",files);
    for (NSString *filePath in files) {
        NSString *path = [sourceCodeDir stringByAppendingPathComponent:filePath];
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            modifyFilesClassName(path, oldClassName, newClassName);
            continue;
        }
        //如果不是文件夹的话那就是文件了，则开始修改文件名前缀
        NSString *fileName = filePath.lastPathComponent;
        if ([fileName hasSuffix:@".h"] || [fileName hasSuffix:@".m"] || [fileName hasSuffix:@".mm"] || [fileName hasSuffix:@".pch"] || [fileName hasSuffix:@".swift"] || [fileName hasSuffix:@".xib"] || [fileName hasSuffix:@".storyboard"]) {
            
            NSError *error = nil;
            NSMutableString *fileContent = [NSMutableString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
            if (error) {
//                printf("打开文件 %s 失败：%s\n", path.UTF8String, error.localizedDescription.UTF8String);
                //当前文件获取失败不能修改，继续下一个文件的修改
                continue;;
//                abort();
            }
            
            NSString *regularExpression = [NSString stringWithFormat:@"\\b%@\\b", oldClassName];
            BOOL isChanged = regularReplacement(fileContent, regularExpression, newClassName);
            if (!isChanged) continue;
            error = nil;
            [fileContent writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
            if (error) {
                printf("保存文件 %s 失败：%s\n", path.UTF8String, error.localizedDescription.UTF8String);
                abort();
            }
        }
    }
}


#pragma mark 获取文件中所有的分类
void getAllCategory(NSMutableString *projectContent, NSString *sourceCodeDir, NSArray<NSString *> *ignoreDirNames, NSString *oldName, NSString *newName) {
    NSFileManager *fm = [NSFileManager defaultManager];
    // 遍历源代码文件 h 与 m 配对，swift
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:sourceCodeDir error:nil];
    BOOL isDirectory;
    for (NSString *filePath in files) {
        NSString *path = [sourceCodeDir stringByAppendingPathComponent:filePath];
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            if (![ignoreDirNames containsObject:filePath]) {
                getAllCategory(projectContent, path, ignoreDirNames, oldName, newName);
            }
            continue;
        }
        
        NSString *fileName = filePath.lastPathComponent.stringByDeletingPathExtension;
        if ([fileName containsString:@"+"]) {
            if (![categoryArr containsObject:fileName]) {
                [categoryArr addObject:fileName];
            }
        }
    }
}


#pragma mark - 修改类名前缀
void modifyClassNamePrefix(NSMutableString *projectContent, NSString *sourceCodeDir, NSArray<NSString *> *ignoreDirNames, NSString *oldName, NSString *newName) {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 遍历源代码文件 h 与 m 配对，swift
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:sourceCodeDir error:nil];
    BOOL isDirectory;
    for (NSString *filePath in files) {
        NSString *path = [sourceCodeDir stringByAppendingPathComponent:filePath];
        if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
            if ([filePath isEqualToString:@"Pods"]) {
                NSLog(@"执行到pods了");
            }
            if (![ignoreDirNames containsObject:filePath]) {
                NSLog(@"：%@",filePath);
                modifyClassNamePrefix(projectContent, path, ignoreDirNames, oldName, newName);
            }
            continue;
        }
        
        
        
        NSString *fileName = filePath.lastPathComponent.stringByDeletingPathExtension;
        if ([fileName isEqualToString:@"MASConstraint"]) {
            NSLog(@"处理的这个文件的名车格式：%@",fileName);
        }
        
        NSString *fileExtension = filePath.pathExtension;
        NSString *newClassName;
        if ([fileName hasPrefix:oldName]) {
            newClassName = [newName stringByAppendingString:[fileName substringFromIndex:oldName.length]];
        } else {
            //处理是category的情况。当是category时，修改+号后面的类名前缀
            NSString *oldNamePlus = [NSString stringWithFormat:@"+%@",oldName];
            if ([fileName containsString:oldNamePlus]) {
                NSMutableString *fileNameStr = [[NSMutableString alloc] initWithString:fileName];
                [fileNameStr replaceCharactersInRange:[fileName rangeOfString:oldNamePlus] withString:[NSString stringWithFormat:@"+%@",newName]];
                newClassName = fileNameStr;
            }else{
                newClassName = [newName stringByAppendingString:fileName];
            }
        }
//        NSLog(@"修改的文件名是：%@",fileName);
        //判断是不是类别 ，如果是uiview+这种系统的类别的话则不去修改类名，否则去修改类名
        NSArray *array = @[@"UI",@"NS",@"MK",@"CL",@"WK"];
        
        BOOL isCustom = YES;
        if ([fileName containsString:@"+"]) {
            NSArray *arr = [fileName componentsSeparatedByString:@"+"];
            if (arr.count > 1) {
                NSString *firstStr = [NSString stringWithFormat:@"%@",arr.firstObject];
                for (NSString *cateStr in array) {
                    if ([firstStr hasPrefix:cateStr]) {
                        isCustom =  NO;
                    }
                }
            }
        }
        
        if ([fileExtension isEqualToString:@"h"]) {
            NSString *mFileName = [fileName stringByAppendingPathExtension:@"m"];
            NSString *mmFileName = [fileName stringByAppendingPathExtension:@"mm"];
            //添加一个
            if (([files containsObject:mFileName] || [files containsObject:mmFileName]) && isCustom) {
                NSString *oldFilePath = [[sourceCodeDir stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:@"h"];
                NSString *newFilePath = [[sourceCodeDir stringByAppendingPathComponent:newClassName] stringByAppendingPathExtension:@"h"];
                renameFile(oldFilePath, newFilePath);
                if ([files containsObject:mmFileName]) {
                    oldFilePath = [[sourceCodeDir stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:@"mm"];
                    newFilePath = [[sourceCodeDir stringByAppendingPathComponent:newClassName] stringByAppendingPathExtension:@"mm"];
                } else {
                    oldFilePath = [[sourceCodeDir stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:@"m"];
                    newFilePath = [[sourceCodeDir stringByAppendingPathComponent:newClassName] stringByAppendingPathExtension:@"m"];
                }
                if ([fileName containsString:@"MapViewController"]) {
                    NSLog(@"这个文件地址是：%@\n%@\n%@",oldFilePath,newFilePath,sourceCodeDir);
                }
                
                renameFile(oldFilePath, newFilePath);
                oldFilePath = [[sourceCodeDir stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:@"xib"];
                if ([fm fileExistsAtPath:oldFilePath]) {
                    newFilePath = [[sourceCodeDir stringByAppendingPathComponent:newClassName] stringByAppendingPathExtension:@"xib"];
                    renameFile(oldFilePath, newFilePath);
                }
                @autoreleasepool {
                    modifyFilesClassName(gSourceCodeDir, fileName, newClassName);
                }
            } else {
                continue;
            }
        } else if ([fileExtension isEqualToString:@"swift"] && isCustom) {
            NSString *oldFilePath = [[sourceCodeDir stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:@"swift"];
            NSString *newFilePath = [[sourceCodeDir stringByAppendingPathComponent:newClassName] stringByAppendingPathExtension:@"swift"];
            renameFile(oldFilePath, newFilePath);
            oldFilePath = [[sourceCodeDir stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:@"xib"];
            if ([fm fileExistsAtPath:oldFilePath]) {
                newFilePath = [[sourceCodeDir stringByAppendingPathComponent:newClassName] stringByAppendingPathExtension:@"xib"];
                renameFile(oldFilePath, newFilePath);
            }
            
            @autoreleasepool {
                modifyFilesClassName(gSourceCodeDir, fileName.stringByDeletingPathExtension, newClassName);
            }
        } else {
            continue;
        }
        
        // 修改工程文件中的文件名
//        NSString *regularExpression = [NSString stringWithFormat:@"\\b%@\\b", fileName];
//        regularReplacement(projectContent, regularExpression, newClassName);
    }
}
