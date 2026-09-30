/** 勋章定义与持久化记录分离，资源仅用于展示。 */
export class MedalDefinition {
  id: string;
  hours: number;
  image: Resource;
  badge: Resource;
  name: Resource;

  constructor(id: string, hours: number, image: Resource, name: Resource, badge: Resource = image) {
    this.id = id;
    this.hours = hours;
    this.image = image;
    this.name = name;
    this.badge = badge;
  }
}

export const MEDALS: MedalDefinition[] = [
  new MedalDefinition('national_day', 0, $r('app.media.national_day_medal'),
    $r('app.string.account_national_day_badge'), $r('app.media.national_day_badge')),
  new MedalDefinition('reading_1h', 1, $r('app.media.reading_medal_1h'), $r('app.string.account_reading_medal_1h_name')),
  new MedalDefinition('reading_10h', 10, $r('app.media.reading_medal_10h'), $r('app.string.account_reading_medal_10h_name')),
  new MedalDefinition('reading_50h', 50, $r('app.media.reading_medal_50h'), $r('app.string.account_reading_medal_50h_name')),
  new MedalDefinition('reading_100h', 100, $r('app.media.reading_medal_100h'), $r('app.string.account_reading_medal_100h_name')),
  new MedalDefinition('reading_300h', 300, $r('app.media.reading_medal_300h'), $r('app.string.account_reading_medal_300h_name')),
  new MedalDefinition('reading_500h', 500, $r('app.media.reading_medal_500h'), $r('app.string.account_reading_medal_500h_name')),
  new MedalDefinition('reading_1000h', 1000, $r('app.media.reading_medal_1000h'), $r('app.string.account_reading_medal_1000h_name')),
  new MedalDefinition('reading_3000h', 3000, $r('app.media.reading_medal_3000h'), $r('app.string.account_reading_medal_3000h_name'))
];

export class MedalAward {
  medalId: string = '';
  unlockedAt: number = 0;
  historical: boolean = true;

  constructor(medalId: string = '', unlockedAt: number = 0, historical: boolean = true) {
    this.medalId = medalId;
    this.unlockedAt = unlockedAt;
    this.historical = historical;
  }
}

export class MedalSnapshot {
  version: number = 1;
  selectedMedalId: string = 'national_day';
  awards: MedalAward[] = [new MedalAward('national_day')];
}
