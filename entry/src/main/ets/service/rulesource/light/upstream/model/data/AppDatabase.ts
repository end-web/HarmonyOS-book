// Project-owned storage boundary; deliberately excluded from the upstream synchronization set.
import { LightSourceDatabase } from '../../../LightSourceRuntime';
export { LightSourceDatabase as AppDatabase } from '../../../LightSourceRuntime';
export const appDb = LightSourceDatabase.getInstance();
