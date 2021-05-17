module kerisy.auth.ShiroCacheManager;

import kerisy.auth.HuntShiroCache;

import hunt.shiro.cache.AbstractCacheManager;
import hunt.shiro.authz.AuthorizationInfo;
import hunt.cache.Cache;
import hunt.shiro.cache.Cache;

import hunt.logging.ConsoleLogger;


/**
 * 
 */
class ShiroCacheManager : AbstractCacheManager!(Object, AuthorizationInfo) {

    private HuntCache _cache;

    this(HuntCache cache){
        _cache = cache;
    }

    override protected HuntShiroCache createCache(string name) {
        return new HuntShiroCache(name, _cache);
    }
}