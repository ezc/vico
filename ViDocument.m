#import "ViDocument.h"
#import "ExTextView.h"
#import "ViLanguageStore.h"

#import "NoodleLineNumberView.h"
#import "NoodleLineNumberMarker.h"
#import "MarkerLineNumberView.h"

BOOL makeNewWindowInsteadOfTab = NO;

@interface ViDocument (internal)
- (ViWindowController *)windowController;
@end

@implementation ViDocument

- (id)init
{
	self = [super init];
	return self;
}

#pragma mark -
#pragma mark NSDocument interface

- (NSString *)windowNibName
{
	return @"ViDocument";
}

- (void)makeWindowControllers
{
	if (makeNewWindowInsteadOfTab)
	{
		windowController = [[ViWindowController alloc] init];
		makeNewWindowInsteadOfTab = NO;
	}
	else
	{
		windowController = [ViWindowController currentWindowController];
	}

	[self addWindowController:windowController];
	[windowController addNewTab:self];
}

- (void)configureSyntax
{
	/* update syntax definition */
	NSDictionary *syntaxOverride = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"syntaxOverride"];
	NSString *syntax = [syntaxOverride objectForKey:[[self fileURL] path]];
	if (syntax)
		[textView setLanguage:syntax];
	else
		[textView configureForURL:[self fileURL]];
	[languageButton selectItemWithTitle:[[textView language] displayName]];
}

- (void)enableLineNumbers:(BOOL)flag
{
	if (flag)
	{
		if (lineNumberView == nil)
		{
			lineNumberView = [[MarkerLineNumberView alloc] initWithScrollView:scrollView];
			[scrollView setVerticalRulerView:lineNumberView];
			[scrollView setHasHorizontalRuler:NO];
			[scrollView setHasVerticalRuler:YES];
		}
		[scrollView setRulersVisible:YES];
	}
	else
		[scrollView setRulersVisible:NO];
}

- (IBAction)toggleLineNumbers:(id)sender
{
	[self enableLineNumbers:[sender state] == NSOffState];
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
	[super windowControllerDidLoadNib:aController];
	[textView initEditorWithDelegate:self];

	[textView setString:readContent];
	[self configureSyntax];

	[statusbar setFont:[NSFont controlContentFontOfSize:11.0]];

	[languageButton removeAllItems];
	[languageButton addItemsWithTitles:[[[ViLanguageStore defaultStore] allLanguageNames] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]];
	[languageButton selectItemWithTitle:[[textView language] displayName]];
	[languageButton setFont:[NSFont controlContentFontOfSize:11.0]];

	[self enableLineNumbers:[[NSUserDefaults standardUserDefaults] boolForKey:@"number"]];

	[symbolsOutline setDataSource:self];
	[symbolsOutline setTarget:self];
	[symbolsOutline setDoubleAction:@selector(goToSymbolAndCloseOutline:)];
	[symbolsOutline setAction:@selector(goToSymbolAndCloseOutline:)];
	NSCell *cell = [(NSTableColumn *)[[symbolsOutline tableColumns] objectAtIndex:0] dataCell];
	[cell setFont:[NSFont systemFontOfSize:10.0]];
	[symbolsOutline setRowHeight:12.0];
	[cell setLineBreakMode:NSLineBreakByTruncatingTail];
	[cell setWraps:NO];

	[splitView setDelegate:self];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	return [[[textView textStorage] string] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	readContent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	return YES;
}

- (void)setFileURL:(NSURL *)absoluteURL
{
	[super setFileURL:absoluteURL];
	[self configureSyntax];
}

#pragma mark -
#pragma mark Other stuff

- (NSView *)view
{
	return view;
}

- (void)changeTheme:(ViTheme *)theme
{
	[textView setTheme:theme];
}

- (void)setPageGuide:(int)pageGuideValue
{
	[textView setPageGuide:pageGuideValue];
}

#pragma mark -
#pragma mark ViTextView delegate methods

- (void)message:(NSString *)fmt, ...
{
	va_list ap;
	va_start(ap, fmt);
	NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
	va_end(ap);

	[statusbar setStringValue:msg];
}

- (IBAction)finishedExCommand:(id)sender
{
	NSString *exCommand = [statusbar stringValue];
	[statusbar setStringValue:@""];
	[statusbar setEditable:NO];
	[[[self windowController] window] makeFirstResponder:textView];
	if ([exCommand length] > 0)
		[textView performSelector:exCommandSelector withObject:exCommand];
}

- (void)getExCommandForTextView:(ViTextView *)aTextView selector:(SEL)aSelector prompt:(NSString *)aPrompt
{
	[statusbar setStringValue:aPrompt];
	[statusbar setEditable:YES];
	[statusbar setDelegate:self];
	exCommandSelector = aSelector;
	[[[self windowController] window] makeFirstResponder:statusbar];
}

- (void)getExCommandForTextView:(ViTextView *)aTextView selector:(SEL)aSelector
{
	[self getExCommandForTextView:aTextView selector:aSelector prompt:@":"];
}

- (BOOL)findPattern:(NSString *)pattern
	    options:(unsigned)find_options
         regexpType:(int)regexpSyntax
{
	return [textView findPattern:pattern options:find_options regexpType:regexpSyntax];
}

// tag push
- (void)pushLine:(NSUInteger)aLine column:(NSUInteger)aColumn
{
	[[[self windowController] sharedTagStack] pushFile:[[self fileURL] path] line:aLine column:aColumn];
}

- (void)popTag
{
	NSDictionary *location = [[[self windowController] sharedTagStack] pop];
	if (location == nil)
	{
		[self message:@"The tags stack is empty"];
		return;
	}

	NSString *file = [location objectForKey:@"file"];
	ViDocument *document = [[NSDocumentController sharedDocumentController]
		openDocumentWithContentsOfURL:[NSURL fileURLWithPath:file] display:YES error:nil];

	if (document)
	{
		[[self windowController] selectDocument:document];
		[[document textView] gotoLine:[[location objectForKey:@"line"] unsignedIntegerValue]
				       column:[[location objectForKey:@"column"] unsignedIntegerValue]];
	}
}

#pragma mark -

- (ViTextView *)textView
{
	return textView;
}

- (ViWindowController *)windowController
{
	return [[self windowControllers] objectAtIndex:0];
}

- (void)close
{
	[self removeWindowController:windowController];
	[super close];
}

#if 0
- (void)shouldCloseWindowController:(NSWindowController *)aWindowController
                           delegate:(id)aDelegate
	        shouldCloseSelector:(SEL)shouldCloseSelector
			contextInfo:(void *)contextInfo
{
	[super shouldCloseWindowController:aWindowController delegate:aDelegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
}
#endif

- (void)canCloseDocumentWithDelegate:(id)aDelegate shouldCloseSelector:(SEL)shouldCloseSelector contextInfo:(void *)contextInfo
{
	[super canCloseDocumentWithDelegate:self shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:contextInfo];
}

- (void)document:(NSDocument *)doc shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
{
	if (shouldClose)
	{
		[windowController removeTabViewItemContainingDocument:self];
		[self close];
		if ([windowController numberOfTabViewItems] == 0)
		{
			/* Close the window after all tabs are gone. */
			[[windowController window] performClose:self];
		}
	}
}

- (IBAction)setLanguage:(id)sender
{
	[textView setLanguage:[sender title]];
	ViLanguage *lang = [textView language];
	if (lang && [self fileURL])
	{
		NSMutableDictionary *syntaxOverride = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"syntaxOverride"]];
		[syntaxOverride setObject:[sender title] forKey:[[self fileURL] path]];
		[[NSUserDefaults standardUserDefaults] setObject:syntaxOverride forKey:@"syntaxOverride"];
	}
}

#pragma mark -
#pragma mark Symbol List

- (void)goToSymbolAndCloseOutline:(id)sender
{
	NSInteger row = [symbolsOutline clickedRow];
	if (row >= 0)
	{
		NSInteger lineno = [[[symbols objectAtIndex:row] objectForKey:@"line"] integerValue];
		[textView gotoLine:lineno column:0];
		[[[self windowController] window] makeFirstResponder:textView];
	}
}

- (void)setSymbols:(NSArray *)aSymbolArray
{
	symbols = aSymbolArray;

	[symbolsOutline reloadData];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	return [[symbols objectAtIndex:rowIndex] objectForKey:@"symbol"];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [symbols count];
}

#pragma mark -
#pragma mark Symbol Split View delegate

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	return YES;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
	return 400;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset
{
	return proposedMax - 100;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex
{
	return YES;
}

- (void)splitView:(id)sender resizeSubviewsWithOldSize:(NSSize)oldSize
{
	NSRect newFrame = [sender frame];
	float dividerThickness = [sender dividerThickness];

	NSView *firstView = [[sender subviews] objectAtIndex:0];
	NSView *secondView = [[sender subviews] objectAtIndex:1];

	NSRect firstFrame = [firstView frame];
	NSRect secondFrame = [secondView frame];

	/* Keep symbol list in constant width. */
	firstFrame.size.width = newFrame.size.width - (secondFrame.size.width + dividerThickness);
	firstFrame.size.height = newFrame.size.height;

	if (firstFrame.size.width < 0)
	{
		firstFrame.size.width = 0;
		secondFrame.size.width = newFrame.size.width - firstFrame.size.width - dividerThickness;
	}

	secondFrame.origin.x = firstFrame.size.width + dividerThickness;

	[firstView setFrame:firstFrame];
	[secondView setFrame:secondFrame];
	[sender adjustSubviews];
}


@end
