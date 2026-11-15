# Keyword research

Run on 2026-11-15 against the US App Store, with autocomplete from US, GB, CA, AU.
Made by `research.mjs`; don't edit by hand, run it again.

How to read it:

- **Demand** (0 to 100) is a proxy, because Apple shares real search volume only inside Apple Ads. A phrase scores higher when App Store autocomplete suggests it, in more storefronts, nearer the top.
- **Difficulty** (0 to 100) rises with how many of the top 10 apps already have the phrase in their title, and with how many ratings those apps have.
- **Score** is demand, discounted by difficulty. High score: people search it and the results are beatable.

## Phrases, best first

| Phrase | Score | Demand | Difficulty | Top 10 with it in the title | Median ratings of top 10 | Autocomplete |
|---|---|---|---|---|---|---|
| delete photos | 76 | 100 | 34 | 0 | 17k | us #3, gb #4, ca #2, au #2 |
| memory cleaner | 72 | 100 | 39 | 1 | 14k | us #2, gb #1, ca #1, au #1 |
| screenshot cleaner | 70 | 100 | 42 | 7 | 0 | us #6, gb #5, ca #2, au #3 |
| swipe photos | 69 | 100 | 44 | 2 | 11k | us #1, gb #1, ca #1, au #1 |
| live photo | 69 | 100 | 43 | 4 | 256 | us #2, gb #3, ca #4, au #3 |
| reduce video size | 68 | 100 | 45 | 3 | 2k | us #1, gb #1, ca #1, au #1 |
| photo swipe | 68 | 100 | 45 | 2 | 12k | us #3, gb #3, ca #2, au #2 |
| gallery cleaner | 66 | 100 | 48 | 3 | 5k | us #1, gb #1, ca #1, au #1 |
| camera roll cleaner | 64 | 100 | 51 | 3 | 12k | us #2, gb #1, ca #1, au #2 |
| compress photos | 61 | 100 | 54 | 5 | 1k | us #2, gb #3, ca #2, au #2 |
| photo compressor | 61 | 100 | 55 | 6 | 268 | us #3, gb #2, ca #1, au #2 |
| duplicate photo remover | 60 | 84 | 40 | 2 | 3k | us #2, gb #1 |
| free up space | 59 | 100 | 57 | 3 | 74k | us #1, gb #1, ca #1, au #1 |
| cleanup | 59 | 100 | 57 | 3 | 85k | us #3, gb #3, ca #4, au #4 |
| shrink video | 58 | 100 | 59 | 5 | 4k | us #2, gb #1, ca #1, au #1 |
| video compressor free | 58 | 73 | 29 | 0 | 4k | us #2, gb #1, ca #1, au #1 |
| junk cleaner | 57 | 84 | 45 | 2 | 14k | us #1, gb #2 |
| free up storage | 56 | 96 | 58 | 3 | 102k | us #3, gb #1, ca #1 |
| burst photos | 56 | 72 | 31 | 3 | 36 | us #1 |
| camera roll cleaner free | 55 | 73 | 34 | 0 | 17k | us #1, gb #2, ca #2, au #1 |
| video compressor | 54 | 100 | 65 | 6 | 4k | us #1, gb #3, ca #2, au #2 |
| swipe delete photos | 53 | 73 | 38 | 1 | 11k | us #1, gb #7, ca #1, au #1 |
| clean storage free | 53 | 73 | 39 | 0 | 67k | us #1, gb #1, ca #1, au #1 |
| photo swiper | 53 | 68 | 30 | 0 | 5k | us #7, gb #4, ca #3, au #3 |
| storage smart entry | 52 | 71 | 38 | 2 | 2k | us #3, gb #3, ca #4, au #2 |
| photo gallery cleaner | 52 | 71 | 37 | 1 | 7k | us #6, gb #3, ca #2, au #3 |
| delete duplicate photos | 52 | 73 | 41 | 1 | 23k | us #9, gb #1, ca #2, au #5 |
| photo cleaner | 50 | 100 | 70 | 6 | 17k | us #1, gb #1, ca #2, au #3 |
| clean storage | 50 | 100 | 70 | 5 | 114k | us #3, gb #2, ca #2, au #2 |
| duplicate photos | 50 | 100 | 70 | 7 | 3k | us #4, gb #4, ca #7, au #3 |
| storage smart | 50 | 66 | 34 | 3 | 94 | us #10, gb #9, ca #10, au #4 |
| compress photos free | 50 | 59 | 21 | 0 | 409 | us #4, gb #2, ca #3 |
| clean up photos | 48 | 68 | 41 | 1 | 23k | us #7, gb #5, ca #3, au #5 |
| storage cleaner | 46 | 100 | 76 | 6 | 102k | us #1, gb #1, ca #2, au #1 |
| resize video | 46 | 100 | 75 | 8 | 2k | us #1, gb #1, ca #1, au #1 |
| duplicate photos fixer | 46 | 61 | 34 | 1 | 3k | us #7, gb #6, ca #6, au #6 |
| remove duplicate photos | 46 | 73 | 52 | 2 | 114k | us #8, gb #7, ca #4, au #1 |
| cleanup 5 | 46 | 58 | 29 | 1 | 826 | us #9, gb #7, ca #7, au #10 |
| storage wars | 44 | 59 | 35 | 3 | 131 | gb #2, ca #3, au #6 |
| cleaner guru free | 43 | 66 | 49 | 3 | 8k | us #7, gb #4, ca #7, au #7 |
| swipe to delete photos | 42 | 61 | 44 | 2 | 11k | gb #1, ca #4, au #7 |
| photo compressor free | 42 | 49 | 20 | 0 | 297 | us #1, au #1 |
| clean up | 41 | 100 | 82 | 7 | 114k | us #4, gb #2, ca #6, au #4 |
| storage | 41 | 100 | 82 | 7 | 109k | us #6, gb #4, ca #8, au #7 |
| compress videos | 41 | 71 | 59 | 5 | 5k | us #4, gb #2, ca #2, au #2 |
| cleanup free | 41 | 61 | 45 | 1 | 74k | gb #1, ca #1, au #1 |
| phone cleaner pro | 40 | 63 | 50 | 3 | 11k | us #5, gb #7, ca #7, au #9 |
| live photo generator | 40 | 51 | 29 | 0 | 5k | us #5, gb #6, au #6 |
| panda video compressor | 40 | 51 | 29 | 0 | 5k | gb #10, ca #5, au #9 |
| storage cleaner free | 39 | 61 | 51 | 2 | 67k | us #5, ca #1, au #1 |
| delete photos free | 39 | 51 | 34 | 0 | 17k | us #5, gb #5, au #6 |
| cleaner | 38 | 100 | 87 | 8 | 85k | us #2, gb #5, ca #5, au #4 |
| phone cleaner | 38 | 100 | 87 | 8 | 74k | us #3, gb #5, ca #4, au #5 |
| free phone cleaner | 38 | 61 | 53 | 3 | 22k | gb #8, ca #5, au #1 |
| clean up storage | 36 | 68 | 66 | 5 | 30k | us #3, gb #10, ca #10, au #8 |
| cleanup photos | 35 | 51 | 44 | 2 | 10k | gb #5, ca #6, au #6 |
| storage treasures | 35 | 47 | 36 | 0 | 32k | us #2, ca #6 |
| resize videos | 34 | 66 | 67 | 6 | 8k | us #7, gb #4, ca #4, au #4 |
| app to delete photos | 34 | 49 | 44 | 2 | 10k | gb #6, ca #7, au #8 |
| phone storage cleaner free | 33 | 49 | 45 | 1 | 85k | us #1, gb #1 |
| photo cleaner free | 32 | 44 | 39 | 0 | 74k | us #3, ca #3 |
| video compressor shrink video | 31 | 46 | 47 | 5 | 125 | gb #10, ca #7, au #7 |
| the photo cleaner | 26 | 51 | 70 | 6 | 17k | gb #5, ca #6, au #5 |
| files cleaner | 25 | 35 | 39 | 1 | 15k | not suggested |
| storage full | 24 | 35 | 45 | 2 | 15k | not suggested |
| blurry photos | 24 | 35 | 43 | 2 | 7k | not suggested |
| large files | 22 | 35 | 50 | 3 | 10k | not suggested |
| cleaner for iphone | 22 | 61 | 89 | 9 | 22k | gb #1, ca #1, au #1 |
| similar photos | 21 | 35 | 56 | 8 | 10 | not suggested |
| clean up iphone | 20 | 49 | 82 | 7 | 114k | us #1, ca #5 |
| compress video | 19 | 35 | 65 | 6 | 4k | not suggested |

## Words competitors use

Out of 40 competitors, how many use each word in their title or subtitle.

| Word | Apps | In the title |
|---|---|---|
| cleaner | 22 | 20 |
| storage | 20 | 13 |
| photo | 15 | 8 |
| space | 14 | 3 |
| clean | 13 | 7 |
| video | 13 | 10 |
| photos | 12 | 4 |
| delete | 11 | 0 |
| duplicate | 11 | 4 |
| free | 10 | 3 |
| size | 9 | 1 |
| cleanup | 8 | 6 |
| compress | 8 | 6 |
| compressor | 8 | 7 |
| reduce | 8 | 1 |
| save | 7 | 2 |
| shrink | 5 | 4 |
| swipe | 4 | 1 |
| videos | 4 | 3 |
| resize | 4 | 3 |
| duplicates | 3 | 0 |
| guru | 3 | 3 |
| clever | 2 | 1 |
| organizer | 2 | 0 |
| boost | 2 | 1 |
| image | 2 | 0 |
| remove | 2 | 1 |
| vids | 2 | 1 |

## Competitors

The apps that appear most often in the top 10 across all the phrases searched.

| App | Subtitle | Ratings | Phrases ranked for |
|---|---|---|---|
| [Cleanup: Phone Storage Cleaner](https://apps.apple.com/us/app/cleanup-phone-storage-cleaner/id1510944943) | Photo Clean, Delete Duplicates | 764k | 49 |
| [Cleaner Kit - Clean Up Storage](https://apps.apple.com/us/app/cleaner-kit-clean-up-storage/id1194582243) | Free Up Space, Delete Photos | 355k | 31 |
| [Clever Cleaner: AI CleanUp App](https://apps.apple.com/us/app/clever-cleaner-ai-cleanup-app/id1666645584) | Free Up Phone & Photo Storage | 85k | 27 |
| [Swipewipe: Photo Cleaner](https://apps.apple.com/us/app/swipewipe-photo-cleaner/id1583884012) | Delete Duplicates & Free Space | 102k | 24 |
| [Slidebox: Photo Cleaner App](https://apps.apple.com/us/app/slidebox-photo-cleaner-app/id984305203) | Photo Swipe, Delete, Organizer | 17k | 21 |
| [Cleaner Neat: Clean Up Storage](https://apps.apple.com/us/app/cleaner-neat-clean-up-storage/id1463756032) | Delete Duplicate Phone Photos | 114k | 14 |
| [Compress Videos & Resize Video](https://apps.apple.com/us/app/compress-videos-resize-video/id1473857051) | Compress videos, save space | 18k | 13 |
| [Photo Cleaner ®](https://apps.apple.com/us/app/photo-cleaner/id6473627334) | Swipe to Delete Camera Roll | 5k | 13 |
| [Video Compress - Shrink Videos](https://apps.apple.com/us/app/video-compress-shrink-videos/id1163846234) | Video Compressor, Reduce Size | 12k | 12 |
| [Clean up iPhone .](https://apps.apple.com/us/app/clean-up-iphone/id6763913041) | AI Cleanup & Free Up Storage | 292 | 12 |
| [Phone Storage Cleaner: Free up](https://apps.apple.com/us/app/phone-storage-cleaner-free-up/id6449484412) | Clean iPhone Duplicate Photos | 74k | 11 |
| [Photo & Video Cleaner: Slider](https://apps.apple.com/us/app/photo-video-cleaner-slider/id6444738335) | Swipe to Delete & Save Space | 12k | 11 |
| [Cleaner Guru: Clean Up Storage](https://apps.apple.com/us/app/cleaner-guru-clean-up-storage/id1476380919) | Delete duplicate phone photos | 148k | 10 |
| [Video Compressor-Shrink videos](https://apps.apple.com/us/app/video-compressor-shrink-videos/id1133417726) | Compress videos & photos | 10k | 10 |
| [Boost Cleaner - Clean Up Smart](https://apps.apple.com/us/app/boost-cleaner-clean-up-smart/id1475887456) | Clean Phone Storage | 67k | 9 |
| [Photo Cleaner: Swipe & Cleanup](https://apps.apple.com/us/app/photo-cleaner-swipe-cleanup/id6766554931) | Delete Photos & Clean Up Phone | 60 | 8 |
| [AI Cleaner: Clean Up Storage](https://apps.apple.com/us/app/ai-cleaner-clean-up-storage/id6448330325) | Delete Duplicate Photo & Video | 211k | 7 |
| [CleanMy®Phone: Cleanup Storage](https://apps.apple.com/us/app/cleanmy-phone-cleanup-storage/id1277110040) | Duplicate Photos Cleaner App | 23k | 7 |
| [Compress Photos & Pictures](https://apps.apple.com/us/app/compress-photos-pictures/id1449007043) | Reduce image size, free space | 23k | 7 |
| [Phone Cleaner for iPhone, iPad](https://apps.apple.com/us/app/phone-cleaner-for-iphone-ipad/id1343754771) | Free up space & clean storage | 22k | 7 |
| [Video compressor - save space](https://apps.apple.com/us/app/video-compressor-save-space/id1422359394) | save storage and disk space | 5k | 7 |
| [Video Compressor - HQ Compress](https://apps.apple.com/us/app/video-compressor-hq-compress/id1546946937) | Reduce video size dramatically | 2k | 7 |
| [Remo Duplicate Photos Remover](https://apps.apple.com/us/app/remo-duplicate-photos-remover/id1066797785) | Photo & Video | 14k | 6 |
| [Duplicate Cleaner: Storage](https://apps.apple.com/us/app/duplicate-cleaner-storage/id1185398417) | Remove Photo, Video & Contact | 3k | 6 |
| [Duplicate Photos Fixer](https://apps.apple.com/us/app/duplicate-photos-fixer/id966475595) | Regain Storage Space | 3k | 6 |
| [Free Cleaner Guru](https://apps.apple.com/us/app/free-cleaner-guru/id6756351762) | Clean up your phone | 2k | 6 |
| [Free Cleanup Guru Cleaner AI](https://apps.apple.com/us/app/free-cleanup-guru-cleaner-ai/id6759891604) | Ai Cleanup Phone Clever App | 807 | 6 |
| [Public Storage](https://apps.apple.com/us/app/public-storage/id1537135259) | Easy Self-Storage Management | 104k | 5 |
| [Extra Space Storage](https://apps.apple.com/us/app/extra-space-storage/id1488957920) | Utilities | 27k | 5 |
| [Video Compress - Shrink Vids](https://apps.apple.com/us/app/video-compress-shrink-vids/id997699744) | Reduce size, save memory space | 4k | 5 |
| [Video Compressor - resize all](https://apps.apple.com/us/app/video-compressor-resize-all/id1520371417) | Simple batch vids size reducer | 1k | 5 |
| [Remove Duplicate Photos](https://apps.apple.com/us/app/remove-duplicate-photos/id1597695980) | Cleaning up similar images | 45 | 5 |
| [Clean Up Phone Storage: CleanX](https://apps.apple.com/us/app/clean-up-phone-storage-cleanx/id1575903244) | Duplicate photo, email cleaner | 30k | 4 |
| [Cleaner ・Phone Storage Cleanup](https://apps.apple.com/us/app/cleaner-phone-storage-cleanup/id6445917429) | Delete Duplicate Photos Videos | 10k | 4 |
| [Cleansmith: Photo Cleaner](https://apps.apple.com/us/app/cleansmith-photo-cleaner/id926090192) | Organizer, Cleanup Duplicates | 4k | 4 |
| [Photo Compress - Shrink Pics](https://apps.apple.com/us/app/photo-compress-shrink-pics/id966242098) | Reduce image size & save space | 4k | 4 |
| [Video Compressor & Reduce size](https://apps.apple.com/us/app/video-compressor-reduce-size/id1135183644) | Compress Photo & Clean Storage | 1k | 4 |
| [Video Compressor : Save Space](https://apps.apple.com/us/app/video-compressor-save-space/id1528281985) | Reduce Size, Resize & Shrink | 520 | 4 |
| [Photo Compressor & Resize](https://apps.apple.com/us/app/photo-compressor-resize/id1580297933) | Reduce Size and Save Space | 297 | 4 |
| [Storage Cleaner for Phone](https://apps.apple.com/us/app/storage-cleaner-for-phone/id6813776797) | Al Free Up Space & Boost Speed | 52 | 4 |
