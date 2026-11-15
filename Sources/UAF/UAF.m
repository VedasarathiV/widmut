#import "UAF.h"
#import <dlfcn.h>
#import <objc/runtime.h>

// The asset service and its reset operation were mapped by pared
// (github.com/4evy/pared, MIT).
static NSString *const kFramework =
    @"/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework";
static NSString *const kService = @"com.apple.siri.uaf.subscription.service";

@interface NSObject (UAFPrivate)
+ (id)defaultManager;
+ (NSXPCInterface *)defaultInterface;
+ (id)latestStatusForClients:(NSString *)name error:(NSError **)error;
+ (id)generateInformationWithError:(NSError **)error;
- (id)getAssetSet:(NSString *)name;
- (NSString *)autoAssetType;
- (int64_t)downloadedFilesystemBytes;
- (oneway void)operationWithConfig:(NSDictionary *)configuration
                        completion:(void (^)(NSError *_Nullable))completion;
@end

static NSError *UAFError(NSString *message) {
  return [NSError errorWithDomain:@"removemacai"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

BOOL UAFLoad(void) { return dlopen(kFramework.fileSystemRepresentation, RTLD_NOW) != NULL; }

NSString *UAFAssetType(NSString *assetSet) {
  Class manager = NSClassFromString(@"UAFConfigurationManager");
  if (![manager respondsToSelector:@selector(defaultManager)]) return nil;
  id m = [manager defaultManager];
  if (![m respondsToSelector:@selector(getAssetSet:)]) return nil;
  id set = [m getAssetSet:assetSet];
  if (![set respondsToSelector:@selector(autoAssetType)]) return nil;
  id type = [set autoAssetType];
  return [type isKindOfClass:NSString.class] ? type : nil;
}

int64_t UAFDownloadedBytes(NSString *assetSet, NSError **error) {
  Class manager = NSClassFromString(@"UAFAutoAssetManager");
  if (![manager respondsToSelector:@selector(latestStatusForClients:error:)]) {
    if (error) *error = UAFError(@"asset status interface unavailable");
    return -1;
  }
  id status = [manager latestStatusForClients:assetSet error:error];
  if (![status respondsToSelector:@selector(downloadedFilesystemBytes)]) return -1;
  return [status downloadedFilesystemBytes];
}

NSDictionary *UAFInformation(NSError **error) {
  Class manager = NSClassFromString(@"UAFAssetSetManager");
  if (![manager respondsToSelector:@selector(generateInformationWithError:)]) {
    if (error) *error = UAFError(@"asset inventory interface unavailable");
    return nil;
  }
  id info = [manager generateInformationWithError:error];
  if ([info isKindOfClass:NSString.class]) {
    info = [NSJSONSerialization JSONObjectWithData:[info dataUsingEncoding:NSUTF8StringEncoding]
                                           options:0
                                             error:error];
  }
  if ([info isKindOfClass:NSDictionary.class]) return info;
  if (error && !*error) *error = UAFError(@"asset inventory has an unexpected shape");
  return nil;
}

void UAFResetAssetSets(NSArray<NSString *> *assetSets, void (^completion)(NSError *)) {
  if (assetSets.count == 0) {
    completion(UAFError(@"refusing to reset an empty list of asset sets"));
    return;
  }
  Class interfaceClass = NSClassFromString(@"UAFXPCProxyServiceInterface");
  if (![interfaceClass respondsToSelector:@selector(defaultInterface)]) {
    completion(UAFError(@"asset service interface unavailable"));
    return;
  }
  NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:kService
                                                                        options:0];
  connection.remoteObjectInterface = [interfaceClass defaultInterface];
  [connection resume];
  __block BOOL done = NO;
  void (^finish)(NSError *) = ^(NSError *e) {
    @synchronized(connection) {
      if (done) return;
      done = YES;
    }
    [connection invalidate];
    completion(e);
  };
  // A proxy answers every selector, so check the interface's protocol instead.
  SEL operation = @selector(operationWithConfig:completion:);
  Protocol *protocol = connection.remoteObjectInterface.protocol;
  if (protocol_getMethodDescription(protocol, operation, YES, YES).name == NULL &&
      protocol_getMethodDescription(protocol, operation, NO, YES).name == NULL) {
    finish(UAFError(@"asset service does not accept operations"));
    return;
  }
  id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *e) { finish(e); }];
  [proxy operationWithConfig:@{@"Operation" : @"ResetAssetSets", @"AssetSets" : [assetSets copy]}
                  completion:^(NSError *e) { finish(e); }];
}

int64_t UAFTotalPresentAssetBytes(void) {
  if (!UAFLoad()) return 0;
  NSError *error = nil;
  NSDictionary *info = UAFInformation(&error);
  if (!info) return 0;
  NSArray *assets = info[@"SystemAssets"];
  if (!assets || ![assets isKindOfClass:[NSArray class]]) return 0;
  int64_t total = 0;
  for (NSDictionary *asset in assets) {
    if (![asset isKindOfClass:[NSDictionary class]]) continue;
    NSNumber *present = asset[@"isPresentOnDevice"];
    if (present && [present boolValue]) {
      NSDictionary *meta = asset[@"metadata"];
      if ([meta isKindOfClass:[NSDictionary class]]) {
        id size = meta[@"com.apple.UnifiedAssetFramework.UnarchivedSize"] ?: meta[@"_UnarchivedSize"];
        if (size) {
          total += [size longLongValue];
        }
      }
    }
  }
  return total;
}

NSArray<NSString *> *UAFAllModelSets(void) {
  if (!UAFLoad()) return @[];
  NSError *error = nil;
  NSDictionary *info = UAFInformation(&error);
  if (info && [info isKindOfClass:[NSDictionary class]]) {
    NSDictionary *setIds = info[@"AssetSetIdentifiers"];
    if (setIds && [setIds isKindOfClass:[NSDictionary class]] && setIds.count > 0) {
      return setIds.allKeys;
    }
  }
  return @[
    @"com.apple.modelcatalog",
    @"com.apple.MobileAsset.UAF.FM.Visual",
    @"com.apple.MobileAsset.UAF.FM.Overrides",
    @"com.apple.MobileAsset.UAF.Photos.MagicCleanup",
    @"com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive",
    @"com.apple.summarizationkit",
    @"com.apple.siri.understanding",
    @"com.apple.siri.understanding.nl.overrides",
    @"com.apple.siri.dialog",
    @"com.apple.siri.tts",
    @"com.apple.if.planner",
    @"com.apple.if.planner.overrides",
    @"com.apple.linguisticdata",
    @"com.apple.TKModelMessages",
    @"com.apple.MobileAsset.UAF.Shortcuts.Generator"
  ];
}
