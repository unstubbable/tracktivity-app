//
//  ActivityTableViewController.m
//  LocationTest
//
//  Created by Hendrik Liebau on 23.07.12.
//  Copyright (c) 2012 SinnerSchrader. All rights reserved.
//

#import "TrackTableViewController.h"
#import "Track+Data.h"
#import "WrappedTrackHandler.h"
#import <MapKit/MapKit.h>
#import <QuartzCore/CALayer.h>
#import "GoogleStaticMapsFetcher.h"
#import "Activity.h"
#import "Route.h"
#import "AppDelegate.h"
#import <RestKit/RestKit.h>

@interface TrackTableViewController ()
@property (nonatomic, strong) UIActionSheet *deleteActionSheet;
@end

@implementation TrackTableViewController

@synthesize deleteActionSheet = _deleteActionSheet;

- (void)setupFetchedResultsController
{
	// Implement this method in a conrete subclass.
	[self doesNotRecognizeSelector:_cmd];
}

- (void)deleteTracks
{
	//[self.fetchedResultsController.fetchedObjects makeObjectsPerformSelector:@selector(deleteEntity)];
	//[self saveContext];
	dispatch_queue_t queue = dispatch_queue_create("delete track queue", NULL);
	for (WrappedTrack *wrappedTrack in self.fetchedResultsController.fetchedObjects) {
		NSManagedObjectID *wrappedTrackObjectID = wrappedTrack.objectID;
		dispatch_async(queue, ^{
			NSManagedObjectContext *context = [NSManagedObjectContext contextForCurrentThread];
			WrappedTrack *wt = (WrappedTrack *) [context objectWithID:wrappedTrackObjectID];
			if (wt) {
				[wt deleteEntity];
				NSError *error;
				if (![RKManagedObjectStore.defaultObjectStore save:&error]) {
					NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
				}
			}
		});
	}
	dispatch_release(queue);
}

- (void)deleteThumbnails
{
	for (WrappedTrack *wrappedTrack in self.fetchedResultsController.fetchedObjects) {
		wrappedTrack.track.thumbnail = nil;
		wrappedTrack.updated = [NSDate date];
	}
	[self saveContext];
}

- (IBAction)trashButtonPressed:(UIBarButtonItem *)sender
{
	if (self.deleteActionSheet) return;
	NSString *cancelButtonTitle = NSLocalizedString(@"ActionSheetCancel", @"action sheet cancel button label");
	NSString *destructiveButtonTitle = [NSString stringWithFormat:NSLocalizedString(@"ActionSheetDeleteTracksFormat", @"action sheet button label for deleting activities"), self.title];
	NSString *otherButtonTitle = NSLocalizedString(@"ActionSheetDeleteThumbnails", @"action sheet button label for deleting thumbnails");
	self.deleteActionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:cancelButtonTitle destructiveButtonTitle:destructiveButtonTitle otherButtonTitles:otherButtonTitle, nil];
	[self.deleteActionSheet showFromBarButtonItem:sender animated:YES];
}

#pragma mark UIActionSheetDelegate Methods

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (buttonIndex == actionSheet.destructiveButtonIndex) {
		[self performSelector:@selector(deleteTracks) withObject:nil afterDelay:0];
		//[self deleteTracks];
	} else if (buttonIndex == actionSheet.firstOtherButtonIndex) {
		[self performSelector:@selector(deleteThumbnails) withObject:nil afterDelay:0];
	}
	self.deleteActionSheet = nil;
}

#pragma mark - Table view data source

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *CellIdentifier = @"Recorded Activity Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    WrappedTrack *wrappedTrack = [self.fetchedResultsController objectAtIndexPath:indexPath];
	
	if ([wrappedTrack isKindOfClass:[Activity class]]) {
		Activity *activity = (Activity *) wrappedTrack;
		if (activity.name) {
			cell.textLabel.text = activity.name;
			cell.detailTextLabel.text = [NSDateFormatter localizedStringFromDate:activity.start dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle];
		} else {
			cell.textLabel.text = [NSDateFormatter localizedStringFromDate:activity.start dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle];
			cell.detailTextLabel.text = [NSDateFormatter localizedStringFromDate:activity.end dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle];
		}
	} else if ([wrappedTrack isKindOfClass:[Route class]]) {
		Route *route = (Route *) wrappedTrack;
		cell.textLabel.text = route.name;
		cell.detailTextLabel.text = [NSDateFormatter localizedStringFromDate:route.created dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle];
	}
	UIImage *thumbnail = wrappedTrack.track.thumbnail;
	// Fetch the image again, if this is a retina screen and the saved image was fetched on non-retina device.
	if (thumbnail == nil || ([[UIScreen mainScreen] scale] > 1 && thumbnail.size.width < 54)) {
		cell.imageView.image = [UIImage imageNamed:@"mapThumbnail.png"];
		NSManagedObjectID *wrappedTrackObjectID = wrappedTrack.objectID;
		if (wrappedTrackObjectID.isTemporaryID) { // try again later
			[self.tableView performSelector:@selector(reloadData)];
		} else {
			dispatch_queue_t queue = dispatch_queue_create("thumbnail fetch queue", NULL);
			dispatch_async(queue, ^{
				NSManagedObjectContext *context = [NSManagedObjectContext contextForCurrentThread];
				WrappedTrack *wt = (WrappedTrack *) [context objectWithID:wrappedTrackObjectID];
				if (wt) {
					NSDate *start = [NSDate date];
					NSArray *encodedPolylineStrings = wt.track.encodedPolylineStrings;
					NSTimeInterval time = [start timeIntervalSinceNow];
					NSLog(@"Encoded polyline string in %.0f milliseconds.", time * -1000);
					UIImage *thumbnail = [GoogleStaticMapsFetcher mapImageForEncodedPaths:encodedPolylineStrings width:53 height:53 withLabels:NO];
					if (thumbnail) {
						wt.track.thumbnail = thumbnail;
						wt.updated = [NSDate date];
						NSError *error;
						if (![RKManagedObjectStore.defaultObjectStore save:&error]) {
							NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
						}
					}
				}
			});
			dispatch_release(queue);
		}
	} else {
		cell.imageView.image = thumbnail;
	}
    
    return cell;
}

- (void)saveContext
{
	NSError *error;
	if (![RKManagedObjectStore.defaultObjectStore save:&error]) {
		NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
	}
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
		// Delete the managed object at the given index path.
		WrappedTrack *wrappedTrack = [self.fetchedResultsController objectAtIndexPath:indexPath];
		// If the wrapped track is a synced activity, first delete it from the server.
		if ([wrappedTrack isKindOfClass:[Activity class]]) {
			Activity *activity = (Activity *) wrappedTrack;
			if (activity.tracktivityID) {
				[[RKObjectManager sharedManager] deleteObject:activity delegate:self];
			}
		}
		[wrappedTrack deleteEntity];
		[self saveContext];
    }   
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

#pragma mark RestKit Delegate Methods

- (void)objectLoader:(RKObjectLoader *)objectLoader didFailWithError:(NSError *)error
{
	NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
}

#pragma mark UIViewController Methods

- (void)viewDidLoad
{
    [super viewDidLoad];
	
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
	
	[self performSelectorOnMainThread:@selector(setupFetchedResultsController) withObject:nil waitUntilDone:NO];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
	[self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:YES];
}

#pragma mark Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	NSIndexPath *indexPath = [self.tableView indexPathForCell:sender];
	WrappedTrack *wrappedTrack = [self.fetchedResultsController objectAtIndexPath:indexPath];
	if ([segue.destinationViewController conformsToProtocol:@protocol(WrappedTrackHandler)]) {
		UIViewController <WrappedTrackHandler> *wrappedTrackHandler = (UIViewController <WrappedTrackHandler> *) segue.destinationViewController;
		wrappedTrackHandler.wrappedTrack = wrappedTrack;
		if ([sender isKindOfClass:[UITableViewCell class]]) {
			UITableViewCell *cell = (UITableViewCell *) sender;
			wrappedTrackHandler.title = cell.textLabel.text;
		}
	}
}

@end
