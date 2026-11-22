import Foundation

/// Validates SF Symbol names and maps invented ones ("add.circle", "map-pin", "users") to real symbols.
public enum SymbolResolver {
    /// On device the app installs `{ UIImage(systemName: $0) != nil }` so every real symbol is accepted.
    public static var validator: ((String) -> Bool)?

    public static let known: Set<String> = [
        "house", "house.fill", "house.circle", "gearshape", "gearshape.fill", "gearshape.2", "magnifyingglass", "magnifyingglass.circle",
        "person", "person.fill", "person.circle", "person.circle.fill", "person.crop.circle", "person.crop.circle.fill", "person.2", "person.2.fill",
        "person.3", "person.3.fill", "person.badge.plus", "person.badge.key", "person.crop.square", "person.text.rectangle",
        "star", "star.fill", "star.circle", "star.circle.fill", "star.leadinghalf.filled", "heart", "heart.fill", "heart.circle", "heart.circle.fill",
        "heart.text.square", "heart.text.square.fill", "bell", "bell.fill", "bell.badge", "bell.badge.fill", "bell.slash",
        "envelope", "envelope.fill", "envelope.open", "phone", "phone.fill", "phone.circle", "message", "message.fill", "bubble.left", "bubble.left.fill",
        "bubble.right", "bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill", "text.bubble", "text.bubble.fill", "quote.bubble",
        "paperplane", "paperplane.fill", "calendar", "calendar.circle", "calendar.badge.plus", "calendar.badge.clock", "clock", "clock.fill",
        "clock.arrow.circlepath", "alarm", "alarm.fill", "timer", "stopwatch", "stopwatch.fill", "hourglass",
        "camera", "camera.fill", "photo", "photo.fill", "photo.on.rectangle", "photo.on.rectangle.angled", "photo.stack", "photo.badge.plus",
        "video", "video.fill", "play", "play.fill", "play.circle", "play.circle.fill", "pause", "pause.fill", "pause.circle.fill", "stop.fill",
        "forward.fill", "backward.fill", "forward.end.fill", "backward.end.fill", "shuffle", "repeat", "music.note", "music.note.list",
        "music.mic", "mic", "mic.fill", "headphones", "speaker.fill", "speaker.wave.2.fill", "speaker.wave.3.fill", "speaker.slash.fill",
        "waveform", "radio", "tv", "tv.fill", "film", "film.fill", "theatermasks", "theatermasks.fill", "gamecontroller", "gamecontroller.fill",
        "book", "book.fill", "book.closed", "book.closed.fill", "books.vertical", "books.vertical.fill", "character.book.closed", "graduationcap",
        "graduationcap.fill", "newspaper", "newspaper.fill", "doc", "doc.fill", "doc.text", "doc.text.fill", "doc.on.doc", "doc.richtext",
        "folder", "folder.fill", "archivebox", "archivebox.fill", "tray", "tray.fill", "tray.full", "paperclip", "link", "link.circle",
        "bookmark", "bookmark.fill", "tag", "tag.fill", "ticket", "ticket.fill", "gift", "gift.fill", "cart", "cart.fill", "cart.badge.plus",
        "bag", "bag.fill", "basket", "basket.fill", "creditcard", "creditcard.fill", "banknote", "banknote.fill", "dollarsign.circle",
        "dollarsign.circle.fill", "dollarsign", "eurosign.circle", "sterlingsign.circle", "yensign.circle", "bitcoinsign.circle",
        "chart.bar", "chart.bar.fill", "chart.bar.xaxis", "chart.bar.doc.horizontal", "chart.pie", "chart.pie.fill", "chart.line.uptrend.xyaxis",
        "chart.line.downtrend.xyaxis", "chart.xyaxis.line", "percent", "number", "function", "plus", "plus.circle", "plus.circle.fill",
        "plus.square", "plus.square.fill", "minus", "minus.circle", "minus.circle.fill", "xmark", "xmark.circle", "xmark.circle.fill",
        "checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.seal", "checkmark.seal.fill", "checkmark.shield", "checkmark.shield.fill",
        "checklist", "list.bullet", "list.bullet.rectangle", "list.number", "list.dash", "line.3.horizontal", "line.3.horizontal.decrease.circle",
        "ellipsis", "ellipsis.circle", "ellipsis.circle.fill", "square.grid.2x2", "square.grid.2x2.fill", "square.grid.3x3", "rectangle.grid.2x2",
        "square.and.arrow.up", "square.and.arrow.down", "arrow.down.circle", "arrow.down.circle.fill", "arrow.up.circle", "arrow.up.circle.fill",
        "arrow.right", "arrow.right.circle", "arrow.right.circle.fill", "arrow.left", "arrow.left.circle", "arrow.clockwise", "arrow.counterclockwise",
        "arrow.triangle.2.circlepath", "arrow.up.arrow.down", "arrow.up.right", "arrow.up.right.square", "chevron.right", "chevron.left",
        "chevron.down", "chevron.up", "chevron.backward", "chevron.forward", "chevron.left.forwardslash.chevron.right",
        "info.circle", "info.circle.fill", "questionmark.circle", "questionmark.circle.fill", "exclamationmark.triangle", "exclamationmark.triangle.fill",
        "exclamationmark.circle", "exclamationmark.circle.fill", "lock", "lock.fill", "lock.open", "lock.shield", "lock.shield.fill", "key", "key.fill",
        "shield", "shield.fill", "hand.raised", "hand.raised.fill", "hand.thumbsup", "hand.thumbsup.fill", "hand.thumbsdown", "hand.wave",
        "hand.tap", "hand.tap.fill", "eye", "eye.fill", "eye.slash", "faceid", "touchid", "trash", "trash.fill", "pencil", "pencil.circle",
        "square.and.pencil", "highlighter", "scissors", "paintbrush", "paintbrush.fill", "paintbrush.pointed", "paintpalette", "paintpalette.fill",
        "wand.and.stars", "sparkles", "sparkle", "wand.and.rays", "lightbulb", "lightbulb.fill", "bolt", "bolt.fill", "bolt.circle", "bolt.heart",
        "flame", "flame.fill", "drop", "drop.fill", "leaf", "leaf.fill", "tree", "tree.fill", "camera.macro", "ladybug", "ladybug.fill",
        "pawprint", "pawprint.fill", "hare", "hare.fill", "tortoise", "tortoise.fill", "fish", "fish.fill", "bird", "bird.fill", "hexagon", "hexagon.fill",
        "sun.max", "sun.max.fill", "sun.min", "sunrise", "sunrise.fill", "sunset", "sunset.fill", "moon", "moon.fill", "moon.stars", "moon.stars.fill",
        "cloud", "cloud.fill", "cloud.sun", "cloud.sun.fill", "cloud.rain", "cloud.rain.fill", "cloud.bolt", "cloud.bolt.fill", "cloud.snow", "cloud.fog",
        "snowflake", "wind", "tornado", "humidity", "humidity.fill", "thermometer", "thermometer.medium", "thermometer.sun", "umbrella", "umbrella.fill",
        "beach.umbrella", "mountain.2", "mountain.2.fill", "globe", "globe.americas", "globe.europe.africa", "globe.asia.australia", "map", "map.fill",
        "mappin", "mappin.circle", "mappin.circle.fill", "mappin.and.ellipse", "location", "location.fill", "location.circle", "location.north",
        "signpost.right", "point.topleft.down.to.point.bottomright.curvepath", "car", "car.fill", "bus", "bus.fill", "tram", "tram.fill", "bicycle",
        "airplane", "airplane.circle", "ferry", "fuelpump", "fuelpump.fill", "figure.walk", "figure.run", "figure.hiking", "figure.outdoor.cycle",
        "figure.pool.swim", "figure.yoga", "figure.strengthtraining.traditional", "figure.mind.and.body", "figure.dance", "figure.wave",
        "figure.2.and.child.holdinghands", "figure.and.child.holdinghands", "dumbbell", "dumbbell.fill", "sportscourt", "soccerball", "basketball",
        "football", "tennis.racket", "trophy", "trophy.fill", "medal", "medal.fill", "flag", "flag.fill", "flag.checkered", "target", "scope",
        "bed.double", "bed.double.fill", "brain.head.profile", "brain", "lungs", "lungs.fill", "stethoscope", "cross.case", "cross.case.fill",
        "pills", "pills.fill", "syringe", "bandage", "staroflife", "heart.circle", "waveform.path.ecg", "fork.knife", "fork.knife.circle",
        "cup.and.saucer", "cup.and.saucer.fill", "mug", "mug.fill", "wineglass", "takeoutbag.and.cup.and.straw", "carrot", "birthday.cake",
        "frying.pan", "refrigerator", "oven", "basket", "storefront", "storefront.fill", "building.2", "building.2.fill", "building.columns",
        "building.columns.fill", "house.lodge", "tent", "suitcase", "suitcase.fill", "briefcase", "briefcase.fill", "tshirt", "tshirt.fill",
        "shoe", "eyeglasses", "crown", "crown.fill", "diamond", "diamond.fill", "laptopcomputer", "desktopcomputer", "iphone", "ipad", "applewatch",
        "keyboard", "printer", "display", "server.rack", "cpu", "memorychip", "terminal", "wifi", "antenna.radiowaves.left.and.right",
        "battery.100", "battery.75", "battery.50", "battery.25", "powerplug", "qrcode", "qrcode.viewfinder", "barcode", "barcode.viewfinder",
        "viewfinder", "camera.viewfinder", "shippingbox", "shippingbox.fill", "truck.box", "box.truck", "cube", "cube.fill", "puzzlepiece",
        "puzzlepiece.fill", "rectangle.portrait.and.arrow.right", "rectangle.and.hand.point.up.left", "slider.horizontal.3", "switch.2",
        "speedometer", "gauge.with.dots.needle.67percent", "gauge.with.dots.needle.33percent", "ruler", "scalemass", "scalemass.fill",
        "textformat", "text.alignleft", "character.cursor.ibeam", "calendar.day.timeline.left", "square.stack.3d.up", "rectangle.stack",
        "rectangle.on.rectangle", "app", "app.fill", "app.badge", "apps.iphone", "circle", "circle.fill", "square", "square.fill",
        "triangle", "triangle.fill", "seal", "seal.fill", "capsule", "oval", "smallcircle.filled.circle", "dot.radiowaves.left.and.right",
        "apple.logo", "applelogo", "swift", "hammer", "hammer.fill", "wrench", "wrench.and.screwdriver", "wrench.and.screwdriver.fill",
        "theatermask.and.paintbrush", "music.quarternote.3", "pianokeys", "guitars", "mic.badge.plus", "camera.aperture", "film.stack",
        "popcorn", "gamecontroller.fill", "dice", "dice.fill", "die.face.5", "suit.heart.fill", "suit.club.fill", "suit.spade.fill",
        "sun.haze", "drop.triangle", "leaf.arrow.triangle.circlepath", "arrow.3.trianglepath", "repeat.circle", "infinity", "atom",
        "graduationcap.circle", "pencil.and.outline", "list.clipboard", "clipboard", "note.text", "square.text.square", "doc.badge.plus",
        "envelope.badge", "person.crop.circle.badge.checkmark", "person.crop.circle.badge.plus", "person.2.circle", "hands.clap",
        "face.smiling", "face.smiling.inverse", "hand.point.up.left", "rosette", "checkmark.rectangle", "cart.circle", "bag.circle",
        "giftcard", "safari", "star.bubble", "xmark.octagon.fill", "network", "party.popper", "wrench.fill", "square.stack", "wallet.pass", "wallet.pass.fill", "chart.line.flattrend.xyaxis", "chart.dots.scatter", "arrow.up.forward.app",
    ]

    /// Word → symbol synonyms for invented or descriptive names.
    public static let synonyms: [String: String] = [
        "home": "house.fill", "house": "house.fill", "settings": "gearshape.fill", "setting": "gearshape.fill", "gear": "gearshape.fill",
        "preferences": "gearshape.fill", "search": "magnifyingglass", "find": "magnifyingglass", "explore": "safari", "discover": "sparkles",
        "user": "person.fill", "profile": "person.crop.circle.fill", "account": "person.crop.circle", "avatar": "person.crop.circle.fill",
        "users": "person.2.fill", "people": "person.2.fill", "friends": "person.2.fill", "team": "person.3.fill", "group": "person.3.fill",
        "community": "person.3.fill", "follower": "person.2", "followers": "person.2", "member": "person.fill",
        "favorite": "heart.fill", "favorites": "heart.fill", "like": "heart.fill", "love": "heart.fill", "heart": "heart.fill",
        "star": "star.fill", "rating": "star.fill", "review": "star.bubble", "notification": "bell.fill", "notifications": "bell.fill",
        "bell": "bell.fill", "alert": "exclamationmark.triangle.fill", "warning": "exclamationmark.triangle.fill", "error": "xmark.octagon.fill",
        "mail": "envelope.fill", "email": "envelope.fill", "inbox": "tray.fill", "phone": "phone.fill", "call": "phone.fill", "contact": "person.crop.circle",
        "chat": "bubble.left.and.bubble.right.fill", "message": "message.fill", "messages": "message.fill", "comment": "text.bubble.fill",
        "comments": "text.bubble.fill", "send": "paperplane.fill", "share": "square.and.arrow.up", "calendar": "calendar", "date": "calendar",
        "event": "calendar.badge.clock", "events": "calendar", "schedule": "calendar.badge.clock", "appointment": "calendar.badge.clock",
        "booking": "calendar.badge.plus", "reservation": "calendar.badge.plus", "clock": "clock.fill", "time": "clock.fill", "history": "clock.arrow.circlepath",
        "recent": "clock.arrow.circlepath", "timer": "timer", "alarm": "alarm.fill", "stopwatch": "stopwatch.fill", "deadline": "hourglass",
        "camera": "camera.fill", "photo": "photo.fill", "photos": "photo.on.rectangle", "image": "photo.fill", "gallery": "photo.stack",
        "picture": "photo.fill", "video": "video.fill", "movie": "film.fill", "movies": "film.fill", "film": "film.fill", "tv": "tv.fill",
        "play": "play.fill", "pause": "pause.fill", "stop": "stop.fill", "next": "forward.fill", "previous": "backward.fill", "music": "music.note",
        "song": "music.note", "songs": "music.note.list", "playlist": "music.note.list", "album": "square.stack", "podcast": "mic.fill",
        "mic": "mic.fill", "microphone": "mic.fill", "audio": "waveform", "sound": "speaker.wave.2.fill", "volume": "speaker.wave.2.fill",
        "headphones": "headphones", "radio": "radio", "game": "gamecontroller.fill", "games": "gamecontroller.fill", "gaming": "gamecontroller.fill",
        "book": "book.fill", "books": "books.vertical.fill", "read": "book.fill", "reading": "book.fill", "library": "books.vertical.fill",
        "learn": "graduationcap.fill", "learning": "graduationcap.fill", "school": "graduationcap.fill", "education": "graduationcap.fill",
        "course": "graduationcap.fill", "courses": "graduationcap.fill", "lesson": "book.closed.fill", "lessons": "book.closed.fill",
        "language": "character.book.closed", "quiz": "questionmark.circle.fill", "news": "newspaper.fill", "article": "doc.text.fill",
        "articles": "newspaper.fill", "blog": "doc.richtext", "note": "note.text", "notes": "note.text", "journal": "book.closed.fill",
        "document": "doc.text.fill", "doc": "doc.fill", "file": "doc.fill", "files": "folder.fill", "folder": "folder.fill", "receipt": "doc.text.fill",
        "invoice": "doc.text.fill", "archive": "archivebox.fill", "attachment": "paperclip", "link": "link", "bookmark": "bookmark.fill",
        "tag": "tag.fill", "tags": "tag.fill", "label": "tag.fill", "ticket": "ticket.fill", "tickets": "ticket.fill", "gift": "gift.fill",
        "reward": "gift.fill", "rewards": "gift.fill", "loyalty": "giftcard", "points": "star.circle.fill", "coupon": "ticket.fill",
        "cart": "cart.fill", "basket": "basket.fill", "bag": "bag.fill", "shopping": "bag.fill", "shop": "storefront.fill", "store": "storefront.fill",
        "market": "storefront.fill", "order": "shippingbox.fill", "orders": "shippingbox.fill", "package": "shippingbox.fill", "delivery": "box.truck",
        "shipping": "box.truck", "truck": "box.truck", "product": "cube.fill", "products": "square.grid.2x2.fill", "price": "tag.fill",
        "sale": "tag.fill", "discount": "percent", "tax": "percent", "percent": "percent",
        "money": "dollarsign.circle.fill", "dollar": "dollarsign.circle.fill", "cash": "banknote.fill", "balance": "dollarsign.circle.fill",
        "income": "arrow.down.circle.fill", "expense": "arrow.up.circle.fill", "expenses": "arrow.up.circle.fill", "spending": "creditcard.fill",
        "spend": "creditcard.fill", "payment": "creditcard.fill", "pay": "creditcard.fill", "card": "creditcard.fill", "credit": "creditcard.fill",
        "wallet": "creditcard.fill", "bank": "building.columns.fill", "savings": "banknote.fill", "budget": "chart.pie.fill", "coins": "dollarsign.circle",
        "coin": "dollarsign.circle", "crypto": "bitcoinsign.circle", "bitcoin": "bitcoinsign.circle", "stock": "chart.line.uptrend.xyaxis",
        "stocks": "chart.line.uptrend.xyaxis", "invest": "chart.line.uptrend.xyaxis", "investment": "chart.line.uptrend.xyaxis",
        "revenue": "chart.line.uptrend.xyaxis", "sales": "chart.bar.fill", "profit": "chart.line.uptrend.xyaxis", "growth": "chart.line.uptrend.xyaxis",
        "trend": "chart.line.uptrend.xyaxis", "chart": "chart.bar.fill", "graph": "chart.xyaxis.line", "stats": "chart.bar.fill",
        "statistics": "chart.bar.fill", "analytics": "chart.xyaxis.line", "report": "chart.bar.doc.horizontal", "pie": "chart.pie.fill",
        "dashboard": "square.grid.2x2.fill", "overview": "square.grid.2x2", "grid": "square.grid.2x2", "list": "list.bullet",
        "menu": "line.3.horizontal", "more": "ellipsis.circle", "options": "ellipsis.circle", "filter": "line.3.horizontal.decrease.circle",
        "sort": "arrow.up.arrow.down", "add": "plus.circle.fill", "new": "plus.circle.fill", "create": "plus.circle.fill", "plus": "plus",
        "remove": "minus.circle.fill", "minus": "minus", "delete": "trash.fill", "trash": "trash.fill", "edit": "pencil", "pencil": "pencil",
        "write": "square.and.pencil", "compose": "square.and.pencil", "close": "xmark.circle.fill", "cancel": "xmark.circle.fill",
        "check": "checkmark.circle.fill", "done": "checkmark.circle.fill", "complete": "checkmark.circle.fill", "success": "checkmark.seal.fill",
        "verified": "checkmark.seal.fill", "task": "checklist", "tasks": "checklist", "todo": "checklist", "todos": "checklist", "checklist": "checklist",
        "info": "info.circle.fill", "about": "info.circle", "help": "questionmark.circle.fill", "support": "questionmark.circle", "faq": "questionmark.circle",
        "question": "questionmark.circle.fill", "lock": "lock.fill", "security": "lock.shield.fill", "secure": "lock.shield.fill",
        "privacy": "hand.raised.fill", "password": "key.fill", "key": "key.fill", "shield": "shield.fill", "login": "person.badge.key",
        "signin": "person.badge.key", "logout": "rectangle.portrait.and.arrow.right", "signout": "rectangle.portrait.and.arrow.right",
        "eye": "eye.fill", "view": "eye", "hide": "eye.slash", "faceid": "faceid", "touchid": "touchid", "biometric": "faceid",
        "download": "arrow.down.circle.fill", "upload": "arrow.up.circle.fill", "sync": "arrow.triangle.2.circlepath", "refresh": "arrow.clockwise",
        "reload": "arrow.clockwise", "back": "chevron.backward", "forward": "chevron.forward", "arrow": "arrow.right", "go": "arrow.right.circle.fill",
        "idea": "lightbulb.fill", "tip": "lightbulb.fill", "magic": "wand.and.stars", "ai": "sparkles", "spark": "sparkles", "sparkle": "sparkles",
        "energy": "bolt.fill", "power": "bolt.fill", "bolt": "bolt.fill", "electric": "bolt.fill", "fire": "flame.fill", "flame": "flame.fill",
        "streak": "flame.fill", "hot": "flame.fill", "calories": "flame.fill", "calorie": "flame.fill", "burn": "flame.fill",
        "water": "drop.fill", "drop": "drop.fill", "droplet": "drop.fill", "hydration": "drop.fill", "honey": "drop.fill", "rain": "cloud.rain.fill",
        "leaf": "leaf.fill", "plant": "leaf.fill", "plants": "leaf.fill", "garden": "leaf.fill", "nature": "leaf.fill", "eco": "leaf.fill",
        "tree": "tree.fill", "forest": "tree.fill", "bug": "ladybug.fill", "pest": "ladybug.fill", "bee": "hexagon.fill", "hive": "hexagon.fill",
        "hives": "hexagon.fill", "pet": "pawprint.fill", "pets": "pawprint.fill", "dog": "pawprint.fill", "cat": "pawprint.fill", "paw": "pawprint.fill",
        "animal": "pawprint.fill", "bird": "bird.fill", "fish": "fish.fill",
        "sun": "sun.max.fill", "sunny": "sun.max.fill", "light": "sun.max", "lighting": "sun.max.fill", "moon": "moon.fill", "night": "moon.stars.fill",
        "dark": "moon.fill", "darkmode": "moon.fill", "cloud": "cloud.fill", "cloudy": "cloud.fill", "weather": "cloud.sun.fill", "forecast": "cloud.sun.fill",
        "snow": "snowflake", "wind": "wind", "storm": "cloud.bolt.fill", "temperature": "thermometer.medium", "thermometer": "thermometer.medium",
        "humidity": "humidity.fill", "umbrella": "umbrella.fill", "sunrise": "sunrise.fill", "sunset": "sunset.fill",
        "globe": "globe", "world": "globe", "earth": "globe.americas", "international": "globe", "map": "map.fill", "maps": "map.fill",
        "location": "location.fill", "pin": "mappin.and.ellipse", "place": "mappin.circle.fill", "places": "mappin.and.ellipse", "address": "mappin.and.ellipse",
        "nearby": "location.circle", "directions": "signpost.right", "route": "point.topleft.down.to.point.bottomright.curvepath",
        "distance": "point.topleft.down.to.point.bottomright.curvepath", "travel": "airplane", "trip": "suitcase.fill", "trips": "suitcase.fill",
        "flight": "airplane", "flights": "airplane", "plane": "airplane", "hotel": "bed.double.fill", "hotels": "bed.double.fill",
        "beach": "beach.umbrella", "mountain": "mountain.2.fill", "camping": "tent", "car": "car.fill", "cars": "car.fill", "drive": "car.fill",
        "ride": "car.fill", "taxi": "car.fill", "bus": "bus.fill", "train": "tram.fill", "transit": "tram.fill", "bike": "bicycle", "bicycle": "bicycle",
        "cycling": "figure.outdoor.cycle", "ship": "ferry", "boat": "ferry", "fuel": "fuelpump.fill", "gas": "fuelpump.fill",
        "run": "figure.run", "running": "figure.run", "runner": "figure.run", "jog": "figure.run", "walk": "figure.walk", "walking": "figure.walk",
        "steps": "figure.walk", "step": "figure.walk", "footprints": "figure.walk", "hike": "figure.hiking", "hiking": "figure.hiking",
        "swim": "figure.pool.swim", "swimming": "figure.pool.swim", "yoga": "figure.yoga", "meditation": "figure.mind.and.body", "meditate": "figure.mind.and.body",
        "mindfulness": "brain.head.profile", "mind": "brain.head.profile", "brain": "brain", "dance": "figure.dance", "fitness": "figure.run",
        "workout": "dumbbell.fill", "workouts": "dumbbell.fill", "exercise": "dumbbell.fill", "gym": "dumbbell.fill", "strength": "dumbbell.fill",
        "dumbbell": "dumbbell.fill", "sport": "sportscourt", "sports": "sportscourt", "soccer": "soccerball", "basketball": "basketball",
        "football": "football", "tennis": "tennis.racket", "trophy": "trophy.fill", "win": "trophy.fill", "award": "medal.fill", "medal": "medal.fill",
        "achievement": "trophy.fill", "achievements": "trophy.fill", "leaderboard": "trophy.fill", "flag": "flag.fill", "goal": "target", "goals": "target",
        "target": "target", "challenge": "flag.checkered", "finish": "flag.checkered", "speed": "speedometer", "pace": "speedometer",
        "speedometer": "speedometer", "height": "ruler", "ruler": "ruler", "weight": "scalemass.fill", "scale": "scalemass.fill",
        "health": "heart.text.square.fill", "heartbeat": "waveform.path.ecg", "heartrate": "waveform.path.ecg", "pulse": "waveform.path.ecg",
        "ecg": "waveform.path.ecg", "sleep": "bed.double.fill", "bed": "bed.double.fill", "rest": "bed.double.fill", "doctor": "stethoscope",
        "medical": "cross.case.fill", "hospital": "cross.case.fill", "clinic": "cross.case.fill", "medicine": "pills.fill", "pill": "pills.fill",
        "pills": "pills.fill", "vaccine": "syringe", "lungs": "lungs.fill", "breathe": "lungs.fill", "breathing": "lungs.fill",
        "food": "fork.knife", "restaurant": "fork.knife", "restaurants": "fork.knife", "dining": "fork.knife", "dinner": "fork.knife",
        "lunch": "fork.knife", "breakfast": "cup.and.saucer.fill", "eat": "fork.knife", "recipe": "frying.pan", "recipes": "frying.pan",
        "cook": "frying.pan", "cooking": "frying.pan", "kitchen": "frying.pan", "coffee": "cup.and.saucer.fill", "cafe": "cup.and.saucer.fill",
        "tea": "mug.fill", "drink": "takeoutbag.and.cup.and.straw", "drinks": "takeoutbag.and.cup.and.straw", "wine": "wineglass",
        "bar": "wineglass", "cake": "birthday.cake", "birthday": "birthday.cake", "dessert": "birthday.cake", "vegetable": "carrot",
        "vegetables": "carrot", "grocery": "basket.fill", "groceries": "basket.fill", "takeout": "takeoutbag.and.cup.and.straw",
        "building": "building.2.fill", "office": "building.2.fill", "company": "building.2.fill", "work": "briefcase.fill", "job": "briefcase.fill",
        "jobs": "briefcase.fill", "career": "briefcase.fill", "business": "briefcase.fill", "property": "house.fill", "realestate": "house.fill",
        "rent": "key.fill", "clothes": "tshirt.fill", "clothing": "tshirt.fill", "fashion": "tshirt.fill", "shirt": "tshirt.fill",
        "shoes": "shoe", "shoe": "shoe", "sneaker": "shoe", "sneakers": "shoe", "glasses": "eyeglasses", "jewelry": "diamond.fill",
        "diamond": "diamond.fill", "luxury": "crown.fill", "premium": "crown.fill", "vip": "crown.fill", "pro": "crown.fill", "crown": "crown.fill",
        "beauty": "sparkles", "design": "paintbrush.pointed", "art": "paintpalette.fill", "paint": "paintbrush.fill", "palette": "paintpalette.fill",
        "color": "paintpalette.fill", "theme": "paintpalette.fill", "brush": "paintbrush.fill", "draw": "pencil.and.outline", "code": "chevron.left.forwardslash.chevron.right",
        "developer": "hammer.fill", "build": "hammer.fill", "tools": "wrench.and.screwdriver.fill", "tool": "wrench.fill", "fix": "wrench.fill",
        "terminal": "terminal", "computer": "laptopcomputer", "laptop": "laptopcomputer", "desktop": "desktopcomputer", "mobile": "iphone",
        "device": "iphone", "iphone": "iphone", "tablet": "ipad", "watch": "applewatch", "wifi": "wifi", "internet": "wifi", "network": "network",
        "battery": "battery.100", "charge": "powerplug", "qr": "qrcode", "qrcode": "qrcode", "scan": "qrcode.viewfinder", "barcode": "barcode",
        "puzzle": "puzzlepiece.fill", "dice": "dice.fill", "luck": "dice.fill", "party": "party.popper", "celebrate": "party.popper",
        "smile": "face.smiling", "happy": "face.smiling", "mood": "face.smiling", "clap": "hands.clap", "thumbsup": "hand.thumbsup.fill",
        "wave": "hand.wave", "hello": "hand.wave", "welcome": "hand.wave", "tap": "hand.tap.fill", "touch": "hand.tap.fill", "family": "figure.2.and.child.holdinghands",
        "kids": "figure.and.child.holdinghands", "baby": "figure.and.child.holdinghands", "child": "figure.and.child.holdinghands",
        "theater": "theatermasks.fill", "entertainment": "theatermasks.fill", "concert": "music.mic", "show": "theatermasks.fill",
        "popcorn": "popcorn", "cinema": "popcorn", "piano": "pianokeys", "guitar": "guitars", "upcoming": "calendar.badge.clock",
        "planner": "calendar", "habit": "checkmark.circle.fill", "habits": "checklist", "progress": "chart.bar.fill", "level": "chart.bar.fill",
        "score": "star.circle.fill", "points.circle": "star.circle.fill", "ai.brain": "brain.head.profile", "robot": "cpu", "chip": "cpu",
    ]

    static func isKnown(_ name: String) -> Bool {
        if known.contains(name) { return true }
        return validator?(name) ?? false
    }

    /// Returns a valid SF Symbol for the given (possibly invented) name.
    public static func resolve(_ raw: String, fallback: String = "circle.fill") -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return fallback }
        if isKnown(name) { return name }
        name = name.lowercased()
            .replacingOccurrences(of: "-", with: ".")
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: " ", with: ".")
        for prefix in ["sf.symbol.", "sf.", "symbol.", "systemimage.", "icon.", "ic."] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        if isKnown(name) { return name }
        // Common invented suffixes/prefixes.
        for candidate in [name + ".fill", name.replacingOccurrences(of: ".fill", with: ""), name.replacingOccurrences(of: "figure.", with: "")] where isKnown(candidate) {
            return candidate
        }
        if let direct = synonyms[name.replacingOccurrences(of: ".", with: "")] { return direct }
        let tokens = name.split(separator: ".").map(String.init).filter { !["fill", "circle", "square", "sf", "symbol", "figure", "sign", "icon", "outline", "alt"].contains($0) }
        // Prefer the most specific token (last nouns usually carry meaning: "shopping.bag" → bag).
        for t in tokens.reversed() {
            if let s = synonyms[t] { return s }
            let singular = t.hasSuffix("s") ? String(t.dropLast()) : t
            if let s = synonyms[singular] { return s }
            if isKnown(t) { return t }
            if isKnown(t + ".fill") { return t + ".fill" }
        }
        return fallback
    }

    /// Picks a symbol that represents a free-text concept ("Monthly spending" → creditcard.fill).
    public static func symbol(forConcept text: String, fallback: String = "circle.fill") -> String {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        for w in words.reversed() {
            if let s = synonyms[w] { return s }
            if w.hasSuffix("s"), let s = synonyms[String(w.dropLast())] { return s }
        }
        return fallback
    }
}
