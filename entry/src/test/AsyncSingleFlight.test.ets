import { describe, it, expect } from '@ohos/hypium';
import { AsyncSingleFlight } from '../main/ets/utils/AsyncSingleFlight';

export default function asyncSingleFlightTest() {
  describe('AsyncSingleFlight', () => {
    it('shares one running task across concurrent callers', 0, async () => {
      const singleFlight = new AsyncSingleFlight<string>();
      let calls = 0;
      const task = async (): Promise<string> => {
        calls++;
        await Promise.resolve();
        return 'token';
      };

      const first = singleFlight.run(task);
      const second = singleFlight.run(task);
      const values = await Promise.all([first, second]);

      expect(calls).assertEqual(1);
      expect(values[0]).assertEqual('token');
      expect(values[1]).assertEqual('token');
    });

    it('allows a retry after the running task fails', 0, async () => {
      const singleFlight = new AsyncSingleFlight<string>();
      let calls = 0;
      let rejected = false;
      try {
        await singleFlight.run(async (): Promise<string> => {
          calls++;
          throw new Error('failed');
        });
      } catch (_e) {
        rejected = true;
      }

      const value = await singleFlight.run(async (): Promise<string> => {
        calls++;
        return 'recovered';
      });

      expect(rejected).assertEqual(true);
      expect(calls).assertEqual(2);
      expect(value).assertEqual('recovered');
    });

    it('releases the running task after a synchronous throw', 0, async () => {
      const singleFlight = new AsyncSingleFlight<string>();
      let calls = 0;
      let rejected = false;
      try {
        await singleFlight.run((): Promise<string> => {
          calls++;
          throw new Error('failed before returning a Promise');
        });
      } catch (_e) {
        rejected = true;
      }

      const value = await singleFlight.run(async (): Promise<string> => {
        calls++;
        return 'recovered';
      });

      expect(rejected).assertEqual(true);
      expect(calls).assertEqual(2);
      expect(value).assertEqual('recovered');
    });
  });
}
