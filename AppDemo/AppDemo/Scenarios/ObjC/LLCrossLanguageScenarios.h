#import "LLTaggedObject.h"
#import "LLViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// L14 — LEAK (cycle). ObjC self → Swift viewModel → onChange (block from ObjC) → self.
@interface LL14ProfileViewController : LLViewController
@end

/// Owned by the Swift L15DownloadViewController.
@interface LL15Downloader : LLTaggedObject
@property (nonatomic, copy, nullable) void (^completion)(NSData *_Nullable data);
@end

@class LL16Uploader;
@protocol LL16UploaderDelegate <NSObject>
- (void)uploaderDidFinish:(LL16Uploader *)uploader;
@end

/// Owned by the Swift L16UploadViewController.
@interface LL16Uploader : LLTaggedObject
@property (nonatomic, strong, nullable) id<LL16UploaderDelegate> delegate;   // should be weak
@end

/// L17 — LEAK (cycle). ObjC self → Swift syncer → delegate (strong Swift var) → self.
@interface LL17SyncViewController : LLViewController
@end

/// Owned by the Swift L18ThumbnailViewController.
@interface LL18ThumbnailFetcher : LLTaggedObject
@property (nonatomic, copy, nullable) void (^onThumbnail)(NSData *_Nullable data);
@end

/// L19 — NO LEAK. ObjC self → Swift viewModel → onChange (weakSelf block).
@interface LL19SettingsViewController : LLViewController
@end

NS_ASSUME_NONNULL_END
