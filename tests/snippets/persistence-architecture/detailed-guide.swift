import CoreData

struct LineItemSnapshot { let uuid: UUID }
struct OrderSnapshot { let lines: [LineItemSnapshot] }
final class CDLineItem: NSManagedObject { @NSManaged var uuid: UUID }
final class CDOrder: NSManagedObject { @NSManaged var lines: NSSet? }
func fillNewLineItem(ctx: NSManagedObjectContext, parent: CDOrder, model: LineItemSnapshot) {}
func fillExistingLineItem(_ entity: CDLineItem, from model: LineItemSnapshot) {}

struct Reader {}
struct Writer {}
