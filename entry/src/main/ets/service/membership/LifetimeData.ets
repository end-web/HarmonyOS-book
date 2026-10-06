import { SubscriptionOrder } from './SubscriptionData';

export class LifetimeEnvelope {
  jwsPurchaseOrder: string = '';
}

export class LifetimeOrder extends SubscriptionOrder {
  price: number = 0;
  currency: string = '';
  signedTime: number = 0;
  purchaseOrderRevocationReasonCode?: string;
  revocationTime?: number;
}

/** 仅接受本应用已验签的非消耗型终身会员订单。 */
export class LifetimePolicy {
  static readonly product: string = 'lastVip';
  static readonly applicationId: string = '6917615941058168740';

  static validate(order: LifetimeOrder, sandbox: boolean, now: number): LifetimeOrder | undefined {
    if (!order || order.applicationId !== LifetimePolicy.applicationId ||
      (order.environment !== 'NORMAL' && !(sandbox && order.environment === 'SANDBOX'))) {
      throw new Error('Invalid lifetime application or environment');
    }
    if (order.productId !== LifetimePolicy.product) return undefined;
    if (order.productType !== '1' || typeof order.purchaseToken !== 'string' || !order.purchaseToken ||
      typeof order.purchaseOrderId !== 'string' || !order.purchaseOrderId ||
      !Number.isSafeInteger(order.purchaseTime) || order.purchaseTime <= 0 || order.purchaseTime > now + 60000 ||
      !Number.isSafeInteger(order.signedTime) || order.signedTime < order.purchaseTime || order.signedTime > now + 60000 ||
      !Number.isSafeInteger(order.price) || order.price < 0 || typeof order.currency !== 'string' ||
      !new RegExp('^[A-Z]{3}$').test(order.currency) ||
      (order.finishStatus !== undefined && !['1', '2'].includes(order.finishStatus))) {
      throw new Error('Invalid lifetime order');
    }
    // "0" 也是撤销原因，不能用数值/真假转换漏掉退款订单。
    if (order.purchaseOrderRevocationReasonCode !== undefined || order.revocationTime !== undefined) return undefined;
    return order;
  }
}
