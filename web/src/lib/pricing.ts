// Plans and prices for the pricing page. Keep these in sync with the app's
// ios/StorageApp/Purchases/Plans.swift and with App Store Connect.
//
// Lifetime is deliberately absent: the app offers it only once, after someone
// dismisses the paywall, so it never undercuts the recurring plans here.

export const plans = {
  weekly: { price: 6.99, period: "week" },
  annual: { price: 39.99, period: "year" },
} as const;

export function formatPrice(amount: number) {
  return `$${amount.toFixed(2)}`;
}

/** Annual price per week, and how much it saves against paying weekly for a year. */
export const annualPerWeek = plans.annual.price / 52;
export const annualSavingsPercent = Math.floor((1 - plans.annual.price / (plans.weekly.price * 52)) * 100);

export const freeFeatures = [
  "Scan your whole library on your iPhone",
  "See exactly what's using space",
  "Find big videos, screenshots, and bursts",
  "Delete what you choose, with 30-day undo",
];

export const proFeatures = [
  "Shrink 4K videos without deleting them",
  "Trim long recordings to the good part",
  "Keep Live Photos as stills",
  "Re-save bloated screenshots",
  "Pick the best shot from every burst",
  "No limits on how much you shrink",
];
