// Plans and prices for the pricing page. Keep these in sync with the app's
// ios/StorageApp/Purchases/Plans.swift and with App Store Connect.
//
// Lifetime is deliberately absent: the app offers it only once, after someone
// dismisses the paywall, so it never undercuts the recurring plans here.

export const plans = {
  weekly: { price: 4.99, period: "week" },
  annual: { price: 24.99, period: "year" },
} as const;

export function formatPrice(amount: number) {
  return `$${amount.toFixed(2)}`;
}

/** Annual price per week, and how much it saves against paying weekly for a year. */
export const annualPerWeek = plans.annual.price / 52;
export const annualSavingsPercent = Math.floor((1 - plans.annual.price / (plans.weekly.price * 52)) * 100);

// The split matches the app's CleanupMethod.isPro and Plan.proFeatures
// (ios/StorageApp/Purchases/): free does it by hand, Pro does the heavy
// hitters in one tap.
export const freeFeatures = [
  "Scan your library and see what's using space",
  "Swipe to clean: likely deletes, one at a time, with undo",
  "Keep the best shot of every burst",
  "Clean up big files in a folder you pick in Files",
  "Step-by-step guides for Messages, WhatsApp, Safari and more",
  "Delete what you choose, with 30-day undo",
];

export const proFeatures = [
  "Shrink 4K videos without deleting them",
  "Trim long recordings to the good part",
  "Keep Live Photos as stills, minus the hidden video",
  "Re-save bloated screenshots at a fraction of the size",
  "Clear duplicates, blurry shots and junk in bulk",
  "Clean up all your photos in one tap",
];
