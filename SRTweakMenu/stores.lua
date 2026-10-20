-- By itsMJQ (SR Tweak Menu 1.1 to 1.9.11).
-- The city's stores and crib wardrobes, and the items the clothing and jewelry
-- stores sell (built by build_stores.py; names only, no game data).
return {
  -- { kind, store, its trigger, the navpoint outside its door }
  stores = {
    { "surgeon", "Condos Plastic Surgeon", "shops_sr_city_$condo_surg_000", "shops_sr_city_$condo_surg_out" },
    { "jewelry", "Airport Jewelry", "shops_sr_city_$air_jewel_000", "shops_sr_city_$air_jewel_out" },
    { "hair", "Trainyard Hair", "shops_sr_city_$train_hair_000", "shops_sr_city_$train_hair_out" },
    { "clothing", "High End Retail Clothing", "shops_sr_city_$high_cloth_000", "shops_sr_city_$high_cloth_out" },
    { "clothing", "Red Light Low Clothing", "shops_sr_city_$red_clothing_000", "shops_sr_city_$red_cloth_out" },
    { "clothing", "Saint's Row Low Clothing", "shops_sr_city_$sr_lowcloth000", "shops_sr_city_$sr_lowcloth_out" },
    { "clothing", "Downtown Clothing", "shops_sr_city_$down_cloth_000", "shops_sr_city_$down_cloth_out" },
    { "clothing", "Arena Clothing", "shops_sr_city_$arena_cloth_000", "shops_sr_city_$arena_cloth_out" },
    { "hair", "Apartments Hair", "shops_sr_city_$apart_hair_000", "shops_sr_city_$apart_hair_out" },
    { "clothing", "Barrio Clothing", "shops_sr_city_$bario_cloth_000", "shops_sr_city_$bario_cloth_out" },
    { "jewelry", "High End Retail Jewelry", "shops_sr_city_$high_jewel_000", "shops_sr_city_$high_jewel_out" },
    { "hair", "High End Retail Hair", "shops_sr_city_$high_hair_000", "shops_sr_city_$high_hair_out" },
    { "clothing", "Suburbs Clothing", "shops_sr_city_$burbs_cloth_000", "shops_sr_city_$burbs_cloth_out" },
    { "jewelry", "Chinatown Jewelry", "shops_sr_city_$china_jewel_000", "shops_sr_city_$china_jewel_out" },
    { "surgeon", "Barrio Plastic Surgeon", "shops_sr_city_$barrio_surg_000", "shops_sr_city_$bario_surg_out" },
    { "surgeon", "Downtown Plastic Surgeon", "shops_sr_city_$down_surg_000", "shops_sr_city_$down_surg_out" },
    { "clothing", "Projects Clothing", "shops_sr_city_$proj_cloth_000", "shops_sr_city_$proj_cloth_out" },
    { "jewelry", "Suburbs Jewelry", "shops_sr_city_$burbs_jewel_000", "shops_sr_city_$burbs_jewel_out" },
    { "surgeon", "Saint's Row Plastic Surgeon", "shops_sr_city_$sr_surgeon_000", "shops_sr_city_$sr_surgeon_out" },
    { "clothing", "Truckyard Clothing", "shops_sr_city_$truck_cloth_000", "shops_sr_city_$truck_cloth_out" },
  },
  -- { crib, its wardrobe trigger, where you stand in it }
  wardrobes = {
    { "King Penthouse", "downtown_$crib_clothing000", "downtown_$reload-player" },
    { "Saints Row Loft", "saintsrow_$crib clothing001", "saintsrow_$player_start" },
    { "Lopez Mansion", "barrio_$crib_clothing000", "barrio_$reload-player" },
    { "Price Mansion", "wrsuburb_$crib_clothing000", "wrsuburb_$reload-player" },
  },
  clothing = { "V-neck pullovers", "aisha t-shirts", "azzure t-shirts", "baggy canvas shorts", "baggy chino pants", "baggy jean shorts", "baggy jeans", "bandanas", "baseball caps", "baseball jerseys", "basic belt style A", "basketball jerseys", "basketball shoes", "basketball shorts", "boxers", "buttoned vests", "canvas pants", "canvas shoes", "cargo pants", "cargo shorts", "casual shoes", "chino pants", "chino shorts", "collared pullovers", "cotton wrist bands", "cotton wrist bands1", "cowboy boots", "cowboy hats", "crown belt", "denim jackets", "doo rag", "double breasted suit coats", "dreadlock hat", "driving caps", "fedoras", "fishing caps", "flag", "football jerseys", "hensley shirts", "hiking boots", "hoodies", "jean shorts", "knit caps", "leather jackets", "leather wrist bands", "leather wrist bands1", "letterman jackets", "long sleeve casual shirts", "long sleeve workshirts", "long socks", "loose fit jeans", "mechanic boots", "medium length socks", "muscle shirts", "oval design", "oxfords", "pleated cotton pants", "polos", "puffy coats", "roundneck pullovers", "short sleeve casual shirts", "short sleeve workshirts", "short socks", "sleeveless baseball jerseys", "sleeveless hensleys", "snap-brim caps", "sneakers", "sport coats", "steer head design", "style B", "sweat pants", "t-shirts", "tank tops", "thermal undershirts", "track jackets", "track pants", "turtlenecks", "zippered sweatshirts", "zippered vests" },
  jewelry = { "54-diamond rings", "9-diamond rings", "Africa medallion", "Celtic cross pennant", "Italian horn pennant", "Section9 sunglasses", "Stalker sunglasses", "Ultor Unlimited sunglasses", "ankh pennant", "circular watches", "circular watches1", "clock medallion", "dog tag pennant", "dollar sign medallion", "dollar sign rings", "flat chain bracelets l1", "flat chain bracelets l2", "flat chain bracelets l3", "flat chain bracelets l4", "flat chain bracelets l5", "flat chain bracelets r1", "flat chain bracelets r2", "flat chain bracelets r3", "flat chain bracelets r4", "flat chain bracelets r5", "generic sunglasses", "grenade medallion", "large framed glasses", "large round glasses/sunglasses", "large wheel A medallion", "lion rings", "long chain1", "long chain2", "long chain3", "long chain4", "long chain6", "long chain7", "long chain8", "long chain9", "male symbol medallion", "mid-length chain", "mid-length chain1", "mid-length chain2", "mid-length chain3", "mid-length chain4", "mid-length chain6", "mid-length chain7", "mid-length chain8", "mid-length chain9", "number one medallion", "octagon watches", "octagon watches1", "peace medallion", "piercings left ear lobe", "piercings left ear middle", "piercings left ear tip", "piercings left eyebrow", "piercings lip bottom left", "piercings lip bottom right", "piercings lip top left", "piercings lip top right", "piercings nose middle", "piercings nostril left", "piercings nostril right", "piercings right ear lobe", "piercings right ear middle", "piercings right ear tip", "piercings right eyebrow", "pimp shades", "pistol medallion", "plain rings", "poker chip pennant", "rectangular gemstone rings", "rectangular watches", "rectangular watches1", "round gemstone rings", "short chain", "short chain1", "short chain2", "short chain3", "short chain4", "short chain6", "short chain7", "short chain8", "short chain9", "single diamond rings", "skull pennant", "slim sunglasses", "small round sunglasses", "small wheel medallion", "sports watches", "sports watches1" },
}
