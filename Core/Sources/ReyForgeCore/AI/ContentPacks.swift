import Foundation

public enum Domain: String, CaseIterable, Hashable {
    case finance, fitness, food, coffee, travel, shopping, social, music, education, health, productivity
    case realEstate, crypto, news, gaming, pets, weather, events, beauty, automotive, generic
}

public struct ContentPack {
    public struct Stat { public var title, value, icon, delta: String }
    public struct Item { public var title, subtitle, value, icon: String }
    public struct Product { public var name, price, image, detail: String; public var rating: Double }
    public struct Post { public var author, handle, text, image, time: String; public var likes: Int }
    public struct Field { public var label, key: String; public var keyboard: String }

    public var domain: Domain
    public var keywords: [String]
    public var appName: String
    public var tagline: String
    public var presetID: String
    public var symbol: String
    public var greeting: String
    public var summary: String
    public var stats: [Stat]
    public var chartTitle: String
    public var chartKind: String
    public var chart: [(String, Double)]
    public var gauge: (label: String, value: Double, max: Double)
    public var listTitle: String
    public var listVariable: String
    public var itemNoun: String
    public var items: [Item]
    public var fields: [Field]
    public var products: [Product]
    public var posts: [Post]
    public var categories: [String]
    public var place: String
    public var description: String

    public var addTitle: String { "Add \(itemNoun.lowercased())" }
    public var addScreen: String { "New \(itemNoun.capitalized)" }

    public var chartData: String { chart.map { "\($0.0):\(Value.format(number: $0.1))" }.joined(separator: ",") }

    /// Items as a JSON list for a VAR declaration.
    public var itemsJSON: String {
        Value.array(items.map { .object(["title": .string($0.title), "subtitle": .string($0.subtitle), "value": .string($0.value), "icon": .string($0.icon)]) }).jsonString()
    }

    public var productsJSON: String {
        Value.array(products.map { .object(["name": .string($0.name), "price": .number(Value.parseNumber($0.price) ?? 0), "image": .string($0.image), "detail": .string($0.detail), "rating": .number($0.rating)]) }).jsonString()
    }

    public var postsJSON: String {
        Value.array(posts.map { .object(["author": .string($0.author), "handle": .string($0.handle), "text": .string($0.text), "image": .string($0.image), "time": .string($0.time), "likes": .number(Double($0.likes))]) }).jsonString()
    }
}

public enum ContentPacks {
    static func img(_ seed: String, _ w: Int = 800, _ h: Int = 500) -> String { "https://picsum.photos/seed/\(seed)/\(w)/\(h)" }

    public static let all: [Domain: ContentPack] = {
        var d: [Domain: ContentPack] = [:]
        d[.finance] = ContentPack(
            domain: .finance, keywords: ["finance", "money", "budget", "expense", "expenses", "bank", "banking", "wallet", "savings", "spending", "income", "invest", "budgeting", "accounting", "bills", "payment", "payments", "transactions", "fintech", "loan", "salary"],
            appName: "Pennywise", tagline: "Money, made mindful.", presetID: "ocean", symbol: "dollarsign.circle.fill",
            greeting: "Good morning, Alex", summary: "You're $420 under budget this month",
            stats: [.init(title: "Balance", value: "$12,450", icon: "creditcard.fill", delta: "+2.4%"), .init(title: "Income", value: "$5,200", icon: "arrow.down.circle.fill", delta: "+8%"),
                    .init(title: "Spent", value: "$1,880", icon: "arrow.up.circle.fill", delta: "-3.1%"), .init(title: "Savings", value: "$3,240", icon: "banknote.fill", delta: "+12%")],
            chartTitle: "Spending this week", chartKind: "bar", chart: [("Mon", 42), ("Tue", 68), ("Wed", 25), ("Thu", 91), ("Fri", 57), ("Sat", 120), ("Sun", 34)],
            gauge: ("Monthly budget", 64, 100), listTitle: "Recent transactions", listVariable: "transactions", itemNoun: "Transaction",
            items: [.init(title: "Blue Bottle Coffee", subtitle: "Today · Food & drink", value: "-$6.50", icon: "cup.and.saucer.fill"),
                    .init(title: "Salary", subtitle: "Yesterday · Income", value: "+$2,600", icon: "briefcase.fill"),
                    .init(title: "Whole Foods", subtitle: "Mon · Groceries", value: "-$84.20", icon: "cart.fill"),
                    .init(title: "Netflix", subtitle: "Sun · Subscriptions", value: "-$15.49", icon: "tv.fill")],
            fields: [.init(label: "Title", key: "title", keyboard: "default"), .init(label: "Amount", key: "value", keyboard: "decimal"), .init(label: "Category", key: "subtitle", keyboard: "default")],
            products: [], posts: [], categories: ["All", "Food", "Bills", "Shopping", "Travel"], place: "New York",
            description: "Track spending, set budgets and grow your savings with clear, beautiful insights.")
        d[.fitness] = ContentPack(
            domain: .fitness, keywords: ["fitness", "workout", "workouts", "gym", "running", "run", "runner", "steps", "exercise", "training", "yoga", "cycling", "marathon", "strength", "activity", "calories", "pilates", "hiit", "jog", "jogging", "athlete", "sport"],
            appName: "Stride", tagline: "Move more. Feel better.", presetID: "sunset", symbol: "figure.run",
            greeting: "Let's move, Sam", summary: "You're 2,100 steps from today's goal",
            stats: [.init(title: "Steps", value: "7,900", icon: "figure.walk", delta: "+12%"), .init(title: "Calories", value: "486", icon: "flame.fill", delta: "+5%"),
                    .init(title: "Distance", value: "5.8 km", icon: "point.topleft.down.to.point.bottomright.curvepath", delta: "+0.6"), .init(title: "Heart rate", value: "72 bpm", icon: "heart.fill", delta: "-2")],
            chartTitle: "Weekly activity", chartKind: "bar", chart: [("Mon", 6.2), ("Tue", 8.1), ("Wed", 4.3), ("Thu", 9.7), ("Fri", 7.5), ("Sat", 11.2), ("Sun", 5.4)],
            gauge: ("Move goal", 79, 100), listTitle: "Recent workouts", listVariable: "workouts", itemNoun: "Workout",
            items: [.init(title: "Morning run", subtitle: "Today · 32 min", value: "5.2 km", icon: "figure.run"),
                    .init(title: "Upper body", subtitle: "Yesterday · 45 min", value: "320 kcal", icon: "dumbbell.fill"),
                    .init(title: "Yoga flow", subtitle: "Tue · 25 min", value: "140 kcal", icon: "figure.yoga"),
                    .init(title: "Evening ride", subtitle: "Mon · 58 min", value: "18 km", icon: "figure.outdoor.cycle")],
            fields: [.init(label: "Workout", key: "title", keyboard: "default"), .init(label: "Duration", key: "subtitle", keyboard: "default"), .init(label: "Result", key: "value", keyboard: "default")],
            products: [], posts: [], categories: ["All", "Run", "Strength", "Yoga", "Ride"], place: "Central Park",
            description: "Plan workouts, track progress and close your rings every day.")
        d[.food] = ContentPack(
            domain: .food, keywords: ["food", "restaurant", "restaurants", "recipe", "recipes", "cooking", "cook", "meal", "meals", "delivery", "dining", "menu", "kitchen", "pizza", "burger", "sushi", "bakery", "chef", "eat", "foodie", "grocery", "groceries"],
            appName: "Savor", tagline: "Good food, delivered.", presetID: "sunset", symbol: "fork.knife",
            greeting: "Hungry, Mia?", summary: "Free delivery on orders over $25 tonight",
            stats: [.init(title: "Orders", value: "24", icon: "bag.fill", delta: "+3"), .init(title: "Saved", value: "$62", icon: "tag.fill", delta: "+$8"),
                    .init(title: "Rewards", value: "1,240 pts", icon: "star.circle.fill", delta: "+120"), .init(title: "Favorites", value: "9", icon: "heart.fill", delta: "+1")],
            chartTitle: "Orders this week", chartKind: "line", chart: [("Mon", 1), ("Tue", 0), ("Wed", 2), ("Thu", 1), ("Fri", 3), ("Sat", 4), ("Sun", 2)],
            gauge: ("Next reward", 62, 100), listTitle: "Popular near you", listVariable: "dishes", itemNoun: "Dish",
            items: [.init(title: "Margherita Pizza", subtitle: "Luigi's · 20 min", value: "$14", icon: "fork.knife"),
                    .init(title: "Salmon Poke Bowl", subtitle: "Aloha Bowls · 15 min", value: "$16", icon: "fish.fill"),
                    .init(title: "Smash Burger", subtitle: "Grill House · 25 min", value: "$12", icon: "flame.fill"),
                    .init(title: "Matcha Latte", subtitle: "Leaf Café · 10 min", value: "$5", icon: "cup.and.saucer.fill")],
            fields: [.init(label: "Dish", key: "title", keyboard: "default"), .init(label: "Restaurant", key: "subtitle", keyboard: "default"), .init(label: "Price", key: "value", keyboard: "decimal")],
            products: [.init(name: "Margherita Pizza", price: "14", image: img("pizza", 600, 600), detail: "San Marzano tomato, fior di latte, basil.", rating: 4.8),
                       .init(name: "Poke Bowl", price: "16", image: img("poke", 600, 600), detail: "Salmon, avocado, edamame, sesame rice.", rating: 4.7),
                       .init(name: "Smash Burger", price: "12", image: img("burger", 600, 600), detail: "Double patty, cheddar, house sauce.", rating: 4.6),
                       .init(name: "Ramen", price: "15", image: img("ramen", 600, 600), detail: "Tonkotsu broth, chashu, soft egg.", rating: 4.9)],
            posts: [], categories: ["All", "Pizza", "Healthy", "Burgers", "Asian", "Dessert"], place: "San Francisco",
            description: "Discover great food nearby and get it delivered fast.")
        d[.coffee] = ContentPack(
            domain: .coffee, keywords: ["coffee", "cafe", "café", "espresso", "latte", "barista", "tea", "loyalty", "coffeeshop"],
            appName: "Brew", tagline: "Your daily ritual.", presetID: "coffee", symbol: "cup.and.saucer.fill",
            greeting: "Morning, Jamie ☕️", summary: "2 more drinks until a free coffee",
            stats: [.init(title: "Stars", value: "184", icon: "star.fill", delta: "+12"), .init(title: "Visits", value: "18", icon: "cup.and.saucer.fill", delta: "+2"),
                    .init(title: "Rewards", value: "3", icon: "gift.fill", delta: "+1"), .init(title: "Saved", value: "$24", icon: "tag.fill", delta: "+$4")],
            chartTitle: "Visits this week", chartKind: "bar", chart: [("Mon", 1), ("Tue", 2), ("Wed", 1), ("Thu", 0), ("Fri", 2), ("Sat", 3), ("Sun", 1)],
            gauge: ("Free drink", 80, 100), listTitle: "Recent orders", listVariable: "orders", itemNoun: "Order",
            items: [.init(title: "Oat Flat White", subtitle: "Today · Pickup", value: "$5.20", icon: "cup.and.saucer.fill"),
                    .init(title: "Cold Brew", subtitle: "Yesterday · Pickup", value: "$4.50", icon: "takeoutbag.and.cup.and.straw"),
                    .init(title: "Almond Croissant", subtitle: "Mon · Pickup", value: "$3.75", icon: "birthday.cake"),
                    .init(title: "Matcha Latte", subtitle: "Sun · Delivery", value: "$5.60", icon: "mug.fill")],
            fields: [.init(label: "Drink", key: "title", keyboard: "default"), .init(label: "Notes", key: "subtitle", keyboard: "default"), .init(label: "Price", key: "value", keyboard: "decimal")],
            products: [.init(name: "Flat White", price: "4.8", image: img("flatwhite", 600, 600), detail: "Velvety microfoam over a double ristretto.", rating: 4.9),
                       .init(name: "Cold Brew", price: "4.5", image: img("coldbrew", 600, 600), detail: "Steeped for 18 hours. Smooth and bold.", rating: 4.8),
                       .init(name: "Matcha Latte", price: "5.6", image: img("matcha", 600, 600), detail: "Ceremonial matcha with oat milk.", rating: 4.7),
                       .init(name: "Croissant", price: "3.75", image: img("croissant", 600, 600), detail: "Buttery, flaky, baked this morning.", rating: 4.6)],
            posts: [], categories: ["Hot", "Iced", "Tea", "Bakery"], place: "Seattle",
            description: "Order ahead, earn stars and skip the line at your favorite café.")
        d[.travel] = ContentPack(
            domain: .travel, keywords: ["travel", "trip", "trips", "flight", "flights", "hotel", "hotels", "vacation", "booking", "airbnb", "tour", "tourism", "journey", "explore", "destination", "itinerary", "beach", "adventure"],
            appName: "Wander", tagline: "Go somewhere new.", presetID: "ocean", symbol: "airplane",
            greeting: "Where to next, Leo?", summary: "Your Tokyo trip starts in 12 days",
            stats: [.init(title: "Trips", value: "8", icon: "suitcase.fill", delta: "+1"), .init(title: "Countries", value: "14", icon: "globe", delta: "+2"),
                    .init(title: "Miles", value: "38.2K", icon: "airplane", delta: "+4.1K"), .init(title: "Saved", value: "12", icon: "heart.fill", delta: "+3")],
            chartTitle: "Trip budget", chartKind: "pie", chart: [("Flights", 1200), ("Hotels", 900), ("Food", 450), ("Activities", 300)],
            gauge: ("Packing list", 70, 100), listTitle: "Upcoming trips", listVariable: "trips", itemNoun: "Trip",
            items: [.init(title: "Tokyo, Japan", subtitle: "Dec 4 – Dec 12", value: "8 nights", icon: "airplane"),
                    .init(title: "Lisbon, Portugal", subtitle: "Feb 10 – Feb 15", value: "5 nights", icon: "sun.max.fill"),
                    .init(title: "Banff, Canada", subtitle: "Apr 2 – Apr 7", value: "5 nights", icon: "mountain.2.fill"),
                    .init(title: "Bali, Indonesia", subtitle: "Jun 18 – Jun 28", value: "10 nights", icon: "beach.umbrella")],
            fields: [.init(label: "Destination", key: "title", keyboard: "default"), .init(label: "Dates", key: "subtitle", keyboard: "default"), .init(label: "Length", key: "value", keyboard: "default")],
            products: [.init(name: "Kyoto Ryokan", price: "220", image: img("kyoto", 600, 600), detail: "Traditional inn with onsen and garden views.", rating: 4.9),
                       .init(name: "Lisbon Loft", price: "140", image: img("lisbon", 600, 600), detail: "Sunny loft in Alfama, steps from the tram.", rating: 4.7),
                       .init(name: "Banff Cabin", price: "180", image: img("banff", 600, 600), detail: "Cozy cabin with mountain views and fireplace.", rating: 4.8),
                       .init(name: "Bali Villa", price: "260", image: img("bali", 600, 600), detail: "Private pool villa surrounded by rice fields.", rating: 4.9)],
            posts: [], categories: ["All", "Beaches", "Cities", "Mountains", "Food"], place: "Tokyo",
            description: "Plan trips, book stays and keep every itinerary in your pocket.")
        d[.shopping] = ContentPack(
            domain: .shopping, keywords: ["shop", "store", "ecommerce", "e-commerce", "shopping", "products", "product", "marketplace", "fashion", "clothing", "boutique", "sneakers", "cart", "catalog", "retail", "merch", "buy", "sell"],
            appName: "Lumen", tagline: "Shop the good stuff.", presetID: "royal", symbol: "bag.fill",
            greeting: "New arrivals for you", summary: "Free shipping on orders over $50",
            stats: [.init(title: "Orders", value: "12", icon: "shippingbox.fill", delta: "+2"), .init(title: "Wishlist", value: "18", icon: "heart.fill", delta: "+4"),
                    .init(title: "Points", value: "2,400", icon: "star.circle.fill", delta: "+300"), .init(title: "Coupons", value: "3", icon: "ticket.fill", delta: "+1")],
            chartTitle: "Sales by category", chartKind: "donut", chart: [("Shoes", 42), ("Bags", 28), ("Tops", 18), ("Other", 12)],
            gauge: ("Free shipping", 76, 100), listTitle: "Your orders", listVariable: "orders", itemNoun: "Order",
            items: [.init(title: "Aero Runner Sneakers", subtitle: "Arriving Thursday", value: "$129", icon: "shippingbox.fill"),
                    .init(title: "Canvas Weekender", subtitle: "Delivered Monday", value: "$89", icon: "bag.fill"),
                    .init(title: "Merino Crew", subtitle: "Delivered last week", value: "$68", icon: "tshirt.fill"),
                    .init(title: "Gift Card", subtitle: "Sent to Sam", value: "$50", icon: "giftcard")],
            fields: [.init(label: "Item", key: "title", keyboard: "default"), .init(label: "Status", key: "subtitle", keyboard: "default"), .init(label: "Price", key: "value", keyboard: "decimal")],
            products: [.init(name: "Aero Runner", price: "129", image: img("sneaker", 600, 600), detail: "Featherlight knit runner with responsive foam.", rating: 4.8),
                       .init(name: "Canvas Weekender", price: "89", image: img("weekender", 600, 600), detail: "Waxed canvas duffel with leather trim.", rating: 4.6),
                       .init(name: "Merino Crew", price: "68", image: img("sweater", 600, 600), detail: "Soft, breathable, temperature-regulating.", rating: 4.7),
                       .init(name: "Studio Headphones", price: "199", image: img("headphones", 600, 600), detail: "Active noise cancelling, 40h battery.", rating: 4.9),
                       .init(name: "Desk Lamp", price: "59", image: img("lamp", 600, 600), detail: "Warm dimmable light, wireless charging base.", rating: 4.5),
                       .init(name: "Ceramic Mug", price: "24", image: img("mug", 600, 600), detail: "Hand-glazed stoneware, 12 oz.", rating: 4.8)],
            posts: [], categories: ["All", "New", "Shoes", "Bags", "Home", "Sale"], place: "Los Angeles",
            description: "Discover products you'll love, with fast checkout and free returns.")
        d[.social] = ContentPack(
            domain: .social, keywords: ["social", "community", "friends", "feed", "posts", "followers", "network", "chat", "messaging", "dating", "share", "photos", "instagram", "twitter", "forum", "creator", "influencer"],
            appName: "Circle", tagline: "Share what matters.", presetID: "candy", symbol: "person.2.fill",
            greeting: "Hey Riley 👋", summary: "You have 5 new notifications",
            stats: [.init(title: "Posts", value: "248", icon: "square.grid.2x2.fill", delta: "+6"), .init(title: "Followers", value: "12.4K", icon: "person.2.fill", delta: "+320"),
                    .init(title: "Following", value: "386", icon: "person.badge.plus", delta: "+4"), .init(title: "Likes", value: "48K", icon: "heart.fill", delta: "+1.2K")],
            chartTitle: "Profile views", chartKind: "area", chart: [("Mon", 120), ("Tue", 180), ("Wed", 150), ("Thu", 260), ("Fri", 310), ("Sat", 420), ("Sun", 380)],
            gauge: ("Profile complete", 85, 100), listTitle: "Activity", listVariable: "activity", itemNoun: "Post",
            items: [.init(title: "Maya liked your photo", subtitle: "2 min ago", value: "", icon: "heart.fill"),
                    .init(title: "Jon started following you", subtitle: "15 min ago", value: "", icon: "person.badge.plus"),
                    .init(title: "Ava commented: “Stunning!”", subtitle: "1 h ago", value: "", icon: "text.bubble.fill"),
                    .init(title: "You were mentioned by Leo", subtitle: "3 h ago", value: "", icon: "at")],
            fields: [.init(label: "What's on your mind?", key: "title", keyboard: "default")],
            products: [],
            posts: [.init(author: "Maya Chen", handle: "@maya", text: "Golden hour at the pier never gets old 🌅", image: img("pier", 800, 600), time: "2h", likes: 284),
                    .init(author: "Jon Park", handle: "@jonp", text: "Finally finished my first marathon! 42.2 km of pure grit.", image: img("marathon", 800, 600), time: "4h", likes: 912),
                    .init(author: "Ava Rossi", handle: "@ava", text: "Homemade pasta night 🍝 recipe in comments", image: img("pasta", 800, 600), time: "6h", likes: 431)],
            categories: ["For you", "Following", "Trending"], place: "Los Angeles",
            description: "Connect with friends, share moments and discover communities.")
        d[.music] = ContentPack(
            domain: .music, keywords: ["music", "song", "songs", "playlist", "playlists", "podcast", "podcasts", "audio", "radio", "album", "artist", "spotify", "streaming", "listen", "band", "dj"],
            appName: "Echo", tagline: "Music that moves you.", presetID: "midnight", symbol: "music.note",
            greeting: "Good evening", summary: "Your Daily Mix is ready",
            stats: [.init(title: "Minutes", value: "1,820", icon: "clock.fill", delta: "+140"), .init(title: "Songs", value: "642", icon: "music.note", delta: "+18"),
                    .init(title: "Artists", value: "128", icon: "music.mic", delta: "+5"), .init(title: "Playlists", value: "14", icon: "music.note.list", delta: "+1")],
            chartTitle: "Listening this week", chartKind: "area", chart: [("Mon", 42), ("Tue", 65), ("Wed", 38), ("Thu", 80), ("Fri", 95), ("Sat", 120), ("Sun", 88)],
            gauge: ("Weekly goal", 72, 100), listTitle: "Up next", listVariable: "tracks", itemNoun: "Track",
            items: [.init(title: "Midnight City", subtitle: "M83", value: "4:03", icon: "music.note"),
                    .init(title: "Blinding Lights", subtitle: "The Weeknd", value: "3:20", icon: "music.note"),
                    .init(title: "Levitating", subtitle: "Dua Lipa", value: "3:23", icon: "music.note"),
                    .init(title: "Ocean Eyes", subtitle: "Billie Eilish", value: "3:20", icon: "music.note")],
            fields: [.init(label: "Song", key: "title", keyboard: "default"), .init(label: "Artist", key: "subtitle", keyboard: "default")],
            products: [], posts: [], categories: ["For you", "Chill", "Focus", "Workout", "Party"], place: "London",
            description: "Stream millions of songs, build playlists and discover new artists.")
        d[.education] = ContentPack(
            domain: .education, keywords: ["education", "learn", "learning", "course", "courses", "lesson", "lessons", "school", "student", "students", "study", "quiz", "language", "tutor", "class", "classes", "university", "flashcards", "teacher", "homework"],
            appName: "Lingo", tagline: "Learn something every day.", presetID: "forest", symbol: "graduationcap.fill",
            greeting: "Welcome back, Kai", summary: "Keep your 12-day streak alive 🔥",
            stats: [.init(title: "Streak", value: "12 days", icon: "flame.fill", delta: "+1"), .init(title: "Words", value: "1,240", icon: "character.book.closed", delta: "+36"),
                    .init(title: "Accuracy", value: "92%", icon: "target", delta: "+3%"), .init(title: "Time", value: "4.5 h", icon: "clock.fill", delta: "+40m")],
            chartTitle: "XP this week", chartKind: "bar", chart: [("Mon", 120), ("Tue", 90), ("Wed", 150), ("Thu", 60), ("Fri", 180), ("Sat", 210), ("Sun", 140)],
            gauge: ("Daily goal", 70, 100), listTitle: "Continue learning", listVariable: "lessons", itemNoun: "Lesson",
            items: [.init(title: "Spanish Basics", subtitle: "Unit 3 · Greetings", value: "70%", icon: "character.book.closed"),
                    .init(title: "Swift for Beginners", subtitle: "Lesson 5 · Optionals", value: "45%", icon: "chevron.left.forwardslash.chevron.right"),
                    .init(title: "World History", subtitle: "Chapter 2 · Rome", value: "20%", icon: "book.closed.fill"),
                    .init(title: "Photography 101", subtitle: "Module 1 · Light", value: "90%", icon: "camera.fill")],
            fields: [.init(label: "Course", key: "title", keyboard: "default"), .init(label: "Next lesson", key: "subtitle", keyboard: "default")],
            products: [], posts: [], categories: ["All", "Languages", "Coding", "Science", "Arts"], place: "Boston",
            description: "Bite-sized lessons, quizzes and streaks that make learning stick.")
        d[.health] = ContentPack(
            domain: .health, keywords: ["health", "medical", "doctor", "medication", "medicine", "pills", "wellness", "sleep", "meditation", "mindfulness", "mental", "therapy", "hydration", "water", "nutrition", "diet", "habit", "habits", "period", "pregnancy", "clinic", "hospital"],
            appName: "Calm Pulse", tagline: "Care for yourself daily.", presetID: "mint", symbol: "heart.text.square.fill",
            greeting: "How are you feeling, Noa?", summary: "You slept 7h 42m last night",
            stats: [.init(title: "Sleep", value: "7h 42m", icon: "bed.double.fill", delta: "+18m"), .init(title: "Water", value: "1.6 L", icon: "drop.fill", delta: "+0.4"),
                    .init(title: "Mindful", value: "15 min", icon: "brain.head.profile", delta: "+5"), .init(title: "Heart", value: "64 bpm", icon: "heart.fill", delta: "-3")],
            chartTitle: "Sleep this week", chartKind: "line", chart: [("Mon", 6.8), ("Tue", 7.2), ("Wed", 6.1), ("Thu", 7.9), ("Fri", 7.4), ("Sat", 8.6), ("Sun", 7.7)],
            gauge: ("Hydration", 64, 100), listTitle: "Today's plan", listVariable: "reminders", itemNoun: "Reminder",
            items: [.init(title: "Vitamin D", subtitle: "8:00 AM · With breakfast", value: "1 pill", icon: "pills.fill"),
                    .init(title: "Drink water", subtitle: "Every 2 hours", value: "250 ml", icon: "drop.fill"),
                    .init(title: "Breathing exercise", subtitle: "1:00 PM", value: "5 min", icon: "lungs.fill"),
                    .init(title: "Wind down", subtitle: "10:30 PM", value: "10 min", icon: "moon.stars.fill")],
            fields: [.init(label: "Reminder", key: "title", keyboard: "default"), .init(label: "When", key: "subtitle", keyboard: "default"), .init(label: "Amount", key: "value", keyboard: "default")],
            products: [], posts: [], categories: ["Today", "Sleep", "Mind", "Body"], place: "Boston",
            description: "Build healthy habits with gentle reminders and insights.")
        d[.productivity] = ContentPack(
            domain: .productivity, keywords: ["todo", "to-do", "tasks", "task", "notes", "note", "productivity", "planner", "calendar", "reminders", "checklist", "project", "projects", "kanban", "focus", "pomodoro", "journal", "organizer", "agenda", "schedule"],
            appName: "Taskly", tagline: "Get things done, calmly.", presetID: "forge", symbol: "checklist",
            greeting: "Good morning, Rey", summary: "You have 5 tasks due today",
            stats: [.init(title: "Due today", value: "5", icon: "calendar", delta: "-1"), .init(title: "Completed", value: "18", icon: "checkmark.circle.fill", delta: "+6"),
                    .init(title: "Focus", value: "2.5 h", icon: "timer", delta: "+30m"), .init(title: "Projects", value: "4", icon: "folder.fill", delta: "+1")],
            chartTitle: "Tasks completed", chartKind: "bar", chart: [("Mon", 4), ("Tue", 6), ("Wed", 3), ("Thu", 7), ("Fri", 5), ("Sat", 2), ("Sun", 1)],
            gauge: ("Weekly goal", 68, 100), listTitle: "Today", listVariable: "tasks", itemNoun: "Task",
            items: [.init(title: "Review pull requests", subtitle: "Work · 10:00 AM", value: "High", icon: "chevron.left.forwardslash.chevron.right"),
                    .init(title: "Call the dentist", subtitle: "Personal · 12:30 PM", value: "Med", icon: "phone.fill"),
                    .init(title: "Plan sprint goals", subtitle: "Work · 3:00 PM", value: "High", icon: "target"),
                    .init(title: "Buy groceries", subtitle: "Home · 6:00 PM", value: "Low", icon: "cart.fill")],
            fields: [.init(label: "Task", key: "title", keyboard: "default"), .init(label: "Details", key: "subtitle", keyboard: "default"), .init(label: "Priority", key: "value", keyboard: "default")],
            products: [], posts: [], categories: ["All", "Work", "Personal", "Home"], place: "San Francisco",
            description: "Capture tasks, plan your day and focus on what matters.")
        d[.realEstate] = ContentPack(
            domain: .realEstate, keywords: ["real estate", "realestate", "property", "properties", "house", "houses", "home", "homes", "apartment", "apartments", "rent", "rental", "listing", "listings", "realtor", "mortgage", "condo"],
            appName: "Nest", tagline: "Find your place.", presetID: "forest", symbol: "house.fill",
            greeting: "Find your next home", summary: "12 new listings match your search",
            stats: [.init(title: "Saved", value: "8", icon: "heart.fill", delta: "+2"), .init(title: "Tours", value: "3", icon: "calendar.badge.clock", delta: "+1"),
                    .init(title: "Avg price", value: "$842K", icon: "dollarsign.circle.fill", delta: "-1.2%"), .init(title: "New", value: "12", icon: "sparkles", delta: "+5")],
            chartTitle: "Median price (K)", chartKind: "line", chart: [("Jan", 810), ("Feb", 822), ("Mar", 835), ("Apr", 830), ("May", 846), ("Jun", 852), ("Jul", 842)],
            gauge: ("Budget fit", 82, 100), listTitle: "New listings", listVariable: "listings", itemNoun: "Listing",
            items: [.init(title: "Sunny 2BR Loft", subtitle: "Mission District · 2 bd · 1 ba", value: "$4,200/mo", icon: "house.fill"),
                    .init(title: "Craftsman Bungalow", subtitle: "Berkeley · 3 bd · 2 ba", value: "$1.29M", icon: "house.lodge"),
                    .init(title: "Modern Condo", subtitle: "SoMa · 1 bd · 1 ba", value: "$689K", icon: "building.2.fill"),
                    .init(title: "Garden Townhouse", subtitle: "Oakland · 3 bd · 2.5 ba", value: "$945K", icon: "leaf.fill")],
            fields: [.init(label: "Address", key: "title", keyboard: "default"), .init(label: "Details", key: "subtitle", keyboard: "default"), .init(label: "Price", key: "value", keyboard: "default")],
            products: [.init(name: "Sunny 2BR Loft", price: "4200", image: img("loft", 800, 600), detail: "Light-filled loft with exposed brick and a private deck.", rating: 4.8),
                       .init(name: "Craftsman Bungalow", price: "1290000", image: img("bungalow", 800, 600), detail: "Restored 1920s craftsman with a garden studio.", rating: 4.9),
                       .init(name: "Modern Condo", price: "689000", image: img("condo", 800, 600), detail: "Floor-to-ceiling windows and skyline views.", rating: 4.6),
                       .init(name: "Garden Townhouse", price: "945000", image: img("townhouse", 800, 600), detail: "Three levels, rooftop terrace, EV parking.", rating: 4.7)],
            posts: [], categories: ["Buy", "Rent", "New", "Open house"], place: "San Francisco",
            description: "Search homes, schedule tours and save your favorites.")
        d[.crypto] = ContentPack(
            domain: .crypto, keywords: ["crypto", "bitcoin", "ethereum", "trading", "stocks", "stock", "portfolio", "investing", "exchange", "nft", "defi", "blockchain", "coins", "market", "markets", "trade"],
            appName: "Ledger", tagline: "Invest with clarity.", presetID: "midnight", symbol: "chart.line.uptrend.xyaxis",
            greeting: "Portfolio", summary: "Up $1,284 (+4.2%) today",
            stats: [.init(title: "Value", value: "$31,904", icon: "chart.line.uptrend.xyaxis", delta: "+4.2%"), .init(title: "Today", value: "+$1,284", icon: "arrow.up.right", delta: "+4.2%"),
                    .init(title: "BTC", value: "$64,210", icon: "bitcoinsign.circle", delta: "+2.8%"), .init(title: "Cash", value: "$2,150", icon: "banknote.fill", delta: "0%")],
            chartTitle: "Portfolio (7d)", chartKind: "area", chart: [("Mon", 29.1), ("Tue", 29.8), ("Wed", 28.6), ("Thu", 30.2), ("Fri", 30.9), ("Sat", 31.2), ("Sun", 31.9)],
            gauge: ("Diversification", 66, 100), listTitle: "Holdings", listVariable: "holdings", itemNoun: "Holding",
            items: [.init(title: "Bitcoin", subtitle: "0.32 BTC", value: "$20,547", icon: "bitcoinsign.circle"),
                    .init(title: "Ethereum", subtitle: "2.4 ETH", value: "$7,920", icon: "diamond.fill"),
                    .init(title: "Apple", subtitle: "12 shares", value: "$2,736", icon: "apple.logo"),
                    .init(title: "S&P 500 ETF", subtitle: "1.4 shares", value: "$701", icon: "chart.bar.fill")],
            fields: [.init(label: "Asset", key: "title", keyboard: "default"), .init(label: "Amount", key: "subtitle", keyboard: "decimal"), .init(label: "Value", key: "value", keyboard: "decimal")],
            products: [], posts: [], categories: ["All", "Crypto", "Stocks", "ETFs"], place: "New York",
            description: "Track your portfolio and the markets in real time.")
        d[.news] = ContentPack(
            domain: .news, keywords: ["news", "article", "articles", "blog", "magazine", "headlines", "journal", "newsletter", "media", "reader", "stories"],
            appName: "Daily Brief", tagline: "What matters, in minutes.", presetID: "mono", symbol: "newspaper.fill",
            greeting: "Today's brief", summary: "5 stories picked for you",
            stats: [.init(title: "Read", value: "42", icon: "book.fill", delta: "+6"), .init(title: "Saved", value: "11", icon: "bookmark.fill", delta: "+2"),
                    .init(title: "Minutes", value: "96", icon: "clock.fill", delta: "+12"), .init(title: "Topics", value: "7", icon: "tag.fill", delta: "+1")],
            chartTitle: "Reading time", chartKind: "bar", chart: [("Mon", 12), ("Tue", 18), ("Wed", 9), ("Thu", 22), ("Fri", 15), ("Sat", 8), ("Sun", 12)],
            gauge: ("Daily goal", 60, 100), listTitle: "Top stories", listVariable: "stories", itemNoun: "Story",
            items: [.init(title: "Apple unveils new MacBook Pro lineup", subtitle: "Tech · 8 min read", value: "2h", icon: "laptopcomputer"),
                    .init(title: "Markets rally on rate-cut hopes", subtitle: "Business · 5 min read", value: "3h", icon: "chart.line.uptrend.xyaxis"),
                    .init(title: "The return of the night train", subtitle: "Travel · 10 min read", value: "5h", icon: "tram.fill"),
                    .init(title: "Inside the race to clean the oceans", subtitle: "Science · 12 min read", value: "7h", icon: "drop.fill")],
            fields: [.init(label: "Headline", key: "title", keyboard: "default"), .init(label: "Section", key: "subtitle", keyboard: "default")],
            products: [], posts: [], categories: ["Top", "Tech", "Business", "World", "Science"], place: "London",
            description: "Curated stories from trusted sources, read in minutes.")
        d[.gaming] = ContentPack(
            domain: .gaming, keywords: ["game", "games", "gaming", "gamer", "esports", "leaderboard", "trivia", "puzzle", "arcade", "tournament", "level", "levels", "score", "scores"],
            appName: "Arcadia", tagline: "Play, compete, win.", presetID: "neon", symbol: "gamecontroller.fill",
            greeting: "Ready, Player One?", summary: "Daily challenge resets in 4h",
            stats: [.init(title: "Level", value: "27", icon: "star.circle.fill", delta: "+1"), .init(title: "Wins", value: "143", icon: "trophy.fill", delta: "+5"),
                    .init(title: "Streak", value: "6", icon: "flame.fill", delta: "+2"), .init(title: "Rank", value: "#214", icon: "medal.fill", delta: "+18")],
            chartTitle: "XP earned", chartKind: "line", chart: [("Mon", 340), ("Tue", 410), ("Wed", 280), ("Thu", 520), ("Fri", 610), ("Sat", 740), ("Sun", 690)],
            gauge: ("Next level", 58, 100), listTitle: "Leaderboard", listVariable: "players", itemNoun: "Player",
            items: [.init(title: "NovaStrike", subtitle: "Level 42", value: "12,840", icon: "crown.fill"),
                    .init(title: "PixelPanda", subtitle: "Level 39", value: "11,920", icon: "medal.fill"),
                    .init(title: "ByteRider", subtitle: "Level 37", value: "10,455", icon: "medal.fill"),
                    .init(title: "You", subtitle: "Level 27", value: "7,310", icon: "person.fill")],
            fields: [.init(label: "Player", key: "title", keyboard: "default"), .init(label: "Level", key: "subtitle", keyboard: "default"), .init(label: "Score", key: "value", keyboard: "number")],
            products: [], posts: [], categories: ["Daily", "Weekly", "All time"], place: "Seoul",
            description: "Compete in daily challenges and climb the global leaderboard.")
        d[.pets] = ContentPack(
            domain: .pets, keywords: ["pet", "pets", "dog", "dogs", "cat", "cats", "puppy", "vet", "veterinary", "grooming", "animal", "animals", "adoption", "walker"],
            appName: "Pawprint", tagline: "Happy pets, happy you.", presetID: "candy", symbol: "pawprint.fill",
            greeting: "Hi Luna's human 🐶", summary: "Luna's walk is due in 30 minutes",
            stats: [.init(title: "Walks", value: "12", icon: "figure.walk", delta: "+2"), .init(title: "Meals", value: "2/3", icon: "fork.knife", delta: ""),
                    .init(title: "Weight", value: "12.4 kg", icon: "scalemass.fill", delta: "-0.2"), .init(title: "Vet visit", value: "Dec 3", icon: "stethoscope", delta: "")],
            chartTitle: "Walk minutes", chartKind: "bar", chart: [("Mon", 30), ("Tue", 45), ("Wed", 25), ("Thu", 50), ("Fri", 40), ("Sat", 70), ("Sun", 55)],
            gauge: ("Activity goal", 74, 100), listTitle: "Care schedule", listVariable: "care", itemNoun: "Care task",
            items: [.init(title: "Morning walk", subtitle: "7:30 AM · 30 min", value: "Done", icon: "figure.walk"),
                    .init(title: "Breakfast", subtitle: "8:00 AM · 1 cup", value: "Done", icon: "fork.knife"),
                    .init(title: "Flea treatment", subtitle: "Monthly", value: "Due", icon: "pills.fill"),
                    .init(title: "Grooming", subtitle: "Saturday · 11:00 AM", value: "Booked", icon: "scissors")],
            fields: [.init(label: "Task", key: "title", keyboard: "default"), .init(label: "When", key: "subtitle", keyboard: "default"), .init(label: "Status", key: "value", keyboard: "default")],
            products: [], posts: [], categories: ["Today", "Health", "Food", "Play"], place: "Austin",
            description: "Track walks, meals and vet visits for every pet in the family.")
        d[.weather] = ContentPack(
            domain: .weather, keywords: ["weather", "forecast", "temperature", "rain", "climate", "storm", "sunny", "humidity", "wind"],
            appName: "Skies", tagline: "Know before you go.", presetID: "ocean", symbol: "cloud.sun.fill",
            greeting: "Manila", summary: "Partly cloudy · Feels like 34°",
            stats: [.init(title: "Humidity", value: "74%", icon: "humidity.fill", delta: ""), .init(title: "Wind", value: "12 km/h", icon: "wind", delta: ""),
                    .init(title: "UV index", value: "8 High", icon: "sun.max.fill", delta: ""), .init(title: "Rain", value: "30%", icon: "cloud.rain.fill", delta: "")],
            chartTitle: "Hourly temperature", chartKind: "line", chart: [("9AM", 28), ("11AM", 30), ("1PM", 32), ("3PM", 33), ("5PM", 31), ("7PM", 29), ("9PM", 27)],
            gauge: ("Air quality", 42, 100), listTitle: "7-day forecast", listVariable: "forecast", itemNoun: "Day",
            items: [.init(title: "Today", subtitle: "Partly cloudy", value: "33° / 26°", icon: "cloud.sun.fill"),
                    .init(title: "Tomorrow", subtitle: "Thunderstorms", value: "31° / 25°", icon: "cloud.bolt.fill"),
                    .init(title: "Wednesday", subtitle: "Rain showers", value: "30° / 25°", icon: "cloud.rain.fill"),
                    .init(title: "Thursday", subtitle: "Sunny", value: "34° / 26°", icon: "sun.max.fill")],
            fields: [.init(label: "City", key: "title", keyboard: "default")],
            products: [], posts: [], categories: ["Today", "Hourly", "10 days"], place: "Manila",
            description: "Accurate forecasts, live conditions and severe weather alerts.")
        d[.events] = ContentPack(
            domain: .events, keywords: ["event", "events", "tickets", "ticket", "concert", "concerts", "festival", "conference", "meetup", "party", "wedding", "rsvp", "venue", "show", "theater"],
            appName: "Gather", tagline: "Find your crowd.", presetID: "royal", symbol: "ticket.fill",
            greeting: "This weekend", summary: "3 events near you match your interests",
            stats: [.init(title: "Going", value: "4", icon: "checkmark.circle.fill", delta: "+1"), .init(title: "Tickets", value: "6", icon: "ticket.fill", delta: "+2"),
                    .init(title: "Saved", value: "15", icon: "bookmark.fill", delta: "+3"), .init(title: "Friends", value: "28", icon: "person.2.fill", delta: "+4")],
            chartTitle: "Events by month", chartKind: "bar", chart: [("Jul", 3), ("Aug", 5), ("Sep", 2), ("Oct", 6), ("Nov", 4), ("Dec", 7)],
            gauge: ("Early bird", 40, 100), listTitle: "Upcoming events", listVariable: "events", itemNoun: "Event",
            items: [.init(title: "Indie Night Live", subtitle: "Fri · 8:00 PM · The Fillmore", value: "$35", icon: "music.mic"),
                    .init(title: "SwiftUI Meetup", subtitle: "Sat · 10:00 AM · Apple Park", value: "Free", icon: "swift"),
                    .init(title: "Street Food Fest", subtitle: "Sun · 12:00 PM · Pier 39", value: "$10", icon: "fork.knife"),
                    .init(title: "Jazz Under Stars", subtitle: "Next Fri · 9:00 PM · Rooftop", value: "$25", icon: "pianokeys")],
            fields: [.init(label: "Event", key: "title", keyboard: "default"), .init(label: "When & where", key: "subtitle", keyboard: "default"), .init(label: "Price", key: "value", keyboard: "default")],
            products: [], posts: [], categories: ["All", "Music", "Tech", "Food", "Art"], place: "San Francisco",
            description: "Discover events, buy tickets and see who's going.")
        d[.beauty] = ContentPack(
            domain: .beauty, keywords: ["beauty", "salon", "spa", "makeup", "skincare", "hair", "nails", "barber", "cosmetics", "massage", "wellness spa"],
            appName: "Glow", tagline: "Look good, feel good.", presetID: "candy", symbol: "sparkles",
            greeting: "Treat yourself, Zoe", summary: "Your facial is tomorrow at 2:00 PM",
            stats: [.init(title: "Visits", value: "9", icon: "calendar", delta: "+1"), .init(title: "Points", value: "860", icon: "star.circle.fill", delta: "+90"),
                    .init(title: "Saved", value: "$45", icon: "tag.fill", delta: "+$10"), .init(title: "Favorites", value: "6", icon: "heart.fill", delta: "+1")],
            chartTitle: "Bookings", chartKind: "bar", chart: [("Jun", 1), ("Jul", 2), ("Aug", 1), ("Sep", 3), ("Oct", 2), ("Nov", 2)],
            gauge: ("Next reward", 86, 100), listTitle: "Services", listVariable: "services", itemNoun: "Service",
            items: [.init(title: "Signature Facial", subtitle: "60 min · Mia", value: "$85", icon: "sparkles"),
                    .init(title: "Haircut & Style", subtitle: "45 min · Jordan", value: "$55", icon: "scissors"),
                    .init(title: "Gel Manicure", subtitle: "40 min · Kim", value: "$40", icon: "hand.raised.fill"),
                    .init(title: "Deep Tissue Massage", subtitle: "90 min · Theo", value: "$120", icon: "figure.mind.and.body")],
            fields: [.init(label: "Service", key: "title", keyboard: "default"), .init(label: "Stylist", key: "subtitle", keyboard: "default"), .init(label: "Price", key: "value", keyboard: "decimal")],
            products: [], posts: [], categories: ["All", "Hair", "Skin", "Nails", "Body"], place: "Los Angeles",
            description: "Book beauty and wellness appointments in seconds.")
        d[.automotive] = ContentPack(
            domain: .automotive, keywords: ["car", "cars", "auto", "automotive", "vehicle", "vehicles", "ev", "charging", "parking", "rideshare", "taxi", "mechanic", "garage", "dealership", "fuel"],
            appName: "Drive", tagline: "Every mile, managed.", presetID: "mono", symbol: "car.fill",
            greeting: "Model 3 · Parked", summary: "Battery at 78% · 412 km range",
            stats: [.init(title: "Battery", value: "78%", icon: "bolt.fill", delta: "+12%"), .init(title: "Range", value: "412 km", icon: "speedometer", delta: ""),
                    .init(title: "Trips", value: "26", icon: "map.fill", delta: "+3"), .init(title: "Cost", value: "$48", icon: "dollarsign.circle.fill", delta: "-$6")],
            chartTitle: "Energy use (kWh)", chartKind: "bar", chart: [("Mon", 8), ("Tue", 12), ("Wed", 6), ("Thu", 14), ("Fri", 10), ("Sat", 18), ("Sun", 9)],
            gauge: ("Charge", 78, 100), listTitle: "Recent trips", listVariable: "drives", itemNoun: "Trip",
            items: [.init(title: "Home → Office", subtitle: "Today · 8:12 AM", value: "18 km", icon: "car.fill"),
                    .init(title: "Supercharger", subtitle: "Yesterday · 35 min", value: "+46 kWh", icon: "bolt.fill"),
                    .init(title: "Weekend getaway", subtitle: "Sat · 2 h 10 min", value: "164 km", icon: "mountain.2.fill"),
                    .init(title: "Grocery run", subtitle: "Fri · 6:40 PM", value: "9 km", icon: "cart.fill")],
            fields: [.init(label: "Trip", key: "title", keyboard: "default"), .init(label: "When", key: "subtitle", keyboard: "default"), .init(label: "Distance", key: "value", keyboard: "default")],
            products: [], posts: [], categories: ["All", "Trips", "Charging", "Service"], place: "Los Angeles",
            description: "Monitor your car, plan charging and review every trip.")
        d[.generic] = ContentPack(
            domain: .generic, keywords: [],
            appName: "My App", tagline: "Built with ReyForge.", presetID: "forge", symbol: "sparkles",
            greeting: "Welcome back", summary: "Here's what's happening today",
            stats: [.init(title: "Active", value: "128", icon: "bolt.fill", delta: "+12%"), .init(title: "Completed", value: "64", icon: "checkmark.circle.fill", delta: "+8%"),
                    .init(title: "This week", value: "23", icon: "calendar", delta: "+3"), .init(title: "Rating", value: "4.8", icon: "star.fill", delta: "+0.1")],
            chartTitle: "This week", chartKind: "bar", chart: [("Mon", 4), ("Tue", 7), ("Wed", 5), ("Thu", 9), ("Fri", 6), ("Sat", 11), ("Sun", 8)],
            gauge: ("Goal", 72, 100), listTitle: "Recent", listVariable: "items", itemNoun: "Item",
            items: [.init(title: "Getting started", subtitle: "Today", value: "New", icon: "sparkles"),
                    .init(title: "Weekly review", subtitle: "Yesterday", value: "Done", icon: "checkmark.circle.fill"),
                    .init(title: "Team sync", subtitle: "Mon", value: "3 notes", icon: "person.2.fill"),
                    .init(title: "Ideas board", subtitle: "Sun", value: "12", icon: "lightbulb.fill")],
            fields: [.init(label: "Title", key: "title", keyboard: "default"), .init(label: "Details", key: "subtitle", keyboard: "default")],
            products: [.init(name: "Starter", price: "9", image: img("starter", 600, 600), detail: "Everything you need to begin.", rating: 4.6),
                       .init(name: "Plus", price: "19", image: img("plus", 600, 600), detail: "More power for growing needs.", rating: 4.7),
                       .init(name: "Pro", price: "39", image: img("pro", 600, 600), detail: "Advanced tools for professionals.", rating: 4.9),
                       .init(name: "Team", price: "79", image: img("team", 600, 600), detail: "Collaborate with your whole team.", rating: 4.8)],
            posts: [.init(author: "Alex Kim", handle: "@alex", text: "Just shipped something new — feedback welcome!", image: img("launch", 800, 600), time: "1h", likes: 128),
                    .init(author: "Sam Lee", handle: "@sam", text: "Morning views from the office ☀️", image: img("office", 800, 600), time: "3h", likes: 76)],
            categories: ["All", "Popular", "New"], place: "San Francisco",
            description: "A beautiful native app built visually with ReyForge.")
        return d
    }()

    public static func pack(_ domain: Domain) -> ContentPack { all[domain] ?? all[.generic]! }

    /// Detects the domain of a free-text topic ("a personal finance app" → .finance).
    public static func detect(_ text: String) -> Domain? {
        let lower = " " + text.lowercased().replacingOccurrences(of: "-", with: " ") + " "
        let words = Set(lower.split(whereSeparator: { !$0.isLetter && $0 != "é" }).map(String.init))
        var best: (Domain, Int)?
        for (domain, pack) in all where domain != .generic {
            var score = 0
            for k in pack.keywords {
                if k.contains(" ") { if lower.contains(" \(k) ") { score += 3 } }
                else if words.contains(k) { score += 2 }
                else if k.count > 4, words.contains(where: { $0.hasPrefix(k) }) { score += 1 }
            }
            if score > 0, score > (best?.1 ?? 0) { best = (domain, score) }
        }
        return best?.0
    }

    /// A generic pack personalised with a topic the curated packs don't cover (e.g. "beekeeping").
    public static func personalized(topic: String) -> ContentPack {
        var p = pack(.generic)
        let title = topic.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        p.appName = title.isEmpty ? p.appName : title
        p.symbol = SymbolResolver.symbol(forConcept: topic, fallback: "sparkles")
        p.summary = "Your \(topic.lowercased()) overview for today"
        p.description = "A beautiful \(topic.lowercased()) app built visually with ReyForge."
        p.items = p.items.enumerated().map { i, item in
            var it = item
            it.title = ["\(title) basics", "Weekly \(topic.lowercased()) review", "\(title) checklist", "\(title) ideas"][i % 4]
            it.icon = p.symbol
            return it
        }
        return p
    }
}
