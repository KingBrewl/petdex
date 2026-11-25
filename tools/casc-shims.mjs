// Newer JavaScript features @rhyster/wow-casc-dbc uses (Temporal, Map.getOrInsert), for Node 24.
import { Temporal } from '@js-temporal/polyfill';
globalThis.Temporal ??= Temporal;
for (const Type of [Map, WeakMap]) {
  Type.prototype.getOrInsert ??= function (key, value) {
    if (!this.has(key)) this.set(key, value);
    return this.get(key);
  };
  Type.prototype.getOrInsertComputed ??= function (key, compute) {
    if (!this.has(key)) this.set(key, compute(key));
    return this.get(key);
  };
}
